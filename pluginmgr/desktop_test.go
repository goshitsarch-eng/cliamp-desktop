package pluginmgr

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bjarneo/cliamp/config"
	"github.com/bjarneo/cliamp/internal/plugintrust"
)

const desktopPluginSource = `plugin.register({name="Example",type="hook",permissions={"control"}})`

func desktopTestDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("CLIAMP_CONFIG_DIR", dir)
	return filepath.Join(dir, "plugins")
}

func approvalFor(review desktopReview) desktopRequest {
	return desktopRequest{Token: review.Token, Source: review.Source, SHA256: review.SHA256, Permissions: review.Permissions}
}

func TestDesktopPrepareDoesNotInstallAndApprovalUsesReviewedBytes(t *testing.T) {
	dir := desktopTestDir(t)
	body := desktopPluginSource
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte(body)) }))
	defer server.Close()
	installTestClient(t, server.URL)
	result, err := desktopAction("prepare", desktopRequest{Source: "owner/cliamp-plugin-example"})
	if err != nil {
		t.Fatal(err)
	}
	review := result["review"].(desktopReview)
	if review.Code != body || review.SHA256 != plugintrust.Hash([]byte(body)) || review.Source != "owner/cliamp-plugin-example" {
		t.Fatal("review differs from download")
	}
	if _, err := os.Stat(filepath.Join(dir, "example.lua")); !os.IsNotExist(err) {
		t.Fatal("prepare installed code before approval")
	}
	body = `plugin.register({name="Changed",type="hook",permissions={"exec"}})`
	if err := approveDesktopReview(dir, "apply", approvalFor(review)); err != nil {
		t.Fatal(err)
	}
	installed, err := os.ReadFile(filepath.Join(dir, "example.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if string(installed) != desktopPluginSource {
		t.Fatal("installed unreviewed remote content")
	}
	manifest, err := plugintrust.Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := plugintrust.Verify(manifest, "example", filepath.Join(dir, "example.lua")); err != nil {
		t.Fatal(err)
	}
	if err := approveDesktopReview(dir, "apply", approvalFor(review)); err == nil {
		t.Fatal("review could be reused")
	}
}

func TestDesktopApprovalRequiresExactReview(t *testing.T) {
	for _, kind := range []string{"source", "hash", "permissions", "action", "token"} {
		t.Run(kind, func(t *testing.T) {
			dir := desktopTestDir(t)
			review, err := saveDesktopReview(dir, "install", "example", "owner/example", []byte(desktopPluginSource))
			if err != nil {
				t.Fatal(err)
			}
			request := approvalFor(review)
			action := "apply"
			switch kind {
			case "source":
				request.Source = "different/source"
			case "hash":
				request.SHA256 = strings.Repeat("0", 64)
			case "permissions":
				request.Permissions = []string{"exec"}
			case "action":
				action = "trust"
			case "token":
				request.Token = "../../bad"
			}
			if err := approveDesktopReview(dir, action, request); err == nil {
				t.Fatal("mismatched approval accepted")
			}
			if _, err := os.Stat(filepath.Join(dir, "example.lua")); !os.IsNotExist(err) {
				t.Fatal("mismatched approval installed plugin")
			}
		})
	}
}

func TestDesktopTrustRejectsFileChangedAfterReview(t *testing.T) {
	dir := desktopTestDir(t)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "example.lua")
	if err := os.WriteFile(path, []byte(desktopPluginSource), 0o600); err != nil {
		t.Fatal(err)
	}
	result, err := desktopAction("review", desktopRequest{Name: "example"})
	if err != nil {
		t.Fatal(err)
	}
	review := result["review"].(desktopReview)
	if err := os.WriteFile(path, []byte(desktopPluginSource+"\n-- changed"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := approveDesktopReview(dir, "trust", approvalFor(review)); err == nil {
		t.Fatal("changed plugin was trusted")
	}
	manifest, err := plugintrust.Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := plugintrust.Verify(manifest, "example", path); err == nil {
		t.Fatal("changed plugin has approval")
	}
}

func TestDesktopConfigureDoesNotExposeSecretsAndCanEnable(t *testing.T) {
	dir := desktopTestDir(t)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "example.lua"), []byte(desktopPluginSource), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := config.SaveSection("plugins", []config.KeyValue{{Key: "disabled", Value: `["example","other"]`}}, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := desktopAction("configure", desktopRequest{Name: "example", Values: map[string]string{"api_key": "desktop-secret-marker", "enabled": "true"}}); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := Desktop("list", strings.NewReader(`{}`), &output); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(output.String(), "desktop-secret-marker") {
		t.Fatal("plugin list exposed a credential")
	}
	var result struct {
		Plugins []desktopPlugin `json:"plugins"`
	}
	if err := json.Unmarshal(output.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if len(result.Plugins) != 1 || !result.Plugins[0].Enabled || len(result.Plugins[0].ConfigKeys) != 1 || result.Plugins[0].ConfigKeys[0] != "api_key" {
		t.Fatalf("plugin state = %+v", result)
	}
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Plugins[""]["disabled"] != "other" || cfg.Plugins["example"]["api_key"] != "desktop-secret-marker" {
		t.Fatal("plugin settings did not round trip")
	}
}

func TestDesktopRemoveRevokesApproval(t *testing.T) {
	dir := desktopTestDir(t)
	review, err := saveDesktopReview(dir, "install", "example", "owner/example", []byte(desktopPluginSource))
	if err != nil {
		t.Fatal(err)
	}
	if err := approveDesktopReview(dir, "apply", approvalFor(review)); err != nil {
		t.Fatal(err)
	}
	if _, err := desktopAction("remove", desktopRequest{Name: "example"}); err != nil {
		t.Fatal(err)
	}
	manifest, err := plugintrust.Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := manifest.Plugins["example"]; ok {
		t.Fatal("removed plugin approval remained")
	}
	if _, err := os.Stat(filepath.Join(dir, "example.lua")); !os.IsNotExist(err) {
		t.Fatal("plugin file remained")
	}
}

func TestDesktopRequestsDoNotEchoInvalidInput(t *testing.T) {
	for _, input := range []string{`{"unknown":"plugin-sensitive-value"}`, `{"source":`, strings.Repeat("x", 65537)} {
		var output bytes.Buffer
		err := Desktop("prepare", strings.NewReader(input), &output)
		if err == nil || strings.Contains(output.String(), "plugin-sensitive-value") {
			t.Fatalf("unsafe error = %v", err)
		}
	}
}
