package cmd

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bjarneo/cliamp/config"
)

func TestPreferencesSchemaExcludesCredentials(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("CLIAMP_CONFIG_DIR", dir)
	data := "buffer_ms = 400\n[navidrome]\npassword = \"private-preference-test\"\nscrobble = false\n[tidal]\nclient_secret = \"private-preference-test\"\n[plugins.example]\ntoken = \"private-preference-test\"\n"
	if err := os.WriteFile(filepath.Join(dir, "config.toml"), []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := PreferencesSchema(&output); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(output.String(), "private-preference-test") || strings.Contains(output.String(), "password") || strings.Contains(output.String(), "client_secret") {
		t.Fatal("preference schema exposed credentials")
	}
	var result struct {
		Values map[string]string `json:"values"`
		Fields []preferenceField `json:"fields"`
	}
	if err := json.Unmarshal(output.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	for key, want := range map[string]string{"buffer_ms": "400", "navidrome.scrobble": "false", "ytmusic.expand_playlist": "true", "plugins.disabled": "[]"} {
		if result.Values[key] != want {
			t.Errorf("%s = %q, want %q", key, result.Values[key], want)
		}
	}
	if len(result.Fields) != len(preferenceFields()) {
		t.Fatal("missing preference fields")
	}
}

func TestPreferencesApplyPreservesSectionsAndComments(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("CLIAMP_CONFIG_DIR", dir)
	path := filepath.Join(dir, "config.toml")
	initial := "# Audio\nbuffer_ms = 250\nunknown = true\n\n[navidrome]\n# Existing account\npassword = \"keep-secret\"\nformat = \"mp3\"\n\n[downloads]\ndirectory = \"old\"\n"
	if err := os.WriteFile(path, []byte(initial), 0o600); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := PreferencesApply(strings.NewReader(`{"buffer_ms":"1000","navidrome.format":"raw","downloads.directory":"/music/saved","eq":"[1,2,3,4,5,6,7,8,9,10]"}`), &output); err != nil {
		t.Fatal(err)
	}
	updated, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, preserved := range []string{"# Audio", "unknown = true", "# Existing account", `password = "keep-secret"`} {
		if !strings.Contains(string(updated), preserved) {
			t.Errorf("lost %s", preserved)
		}
	}
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.BufferMs != 1000 || cfg.Navidrome.Format != "raw" || cfg.Downloads.Directory != "/music/saved" || cfg.EQ[9] != 10 {
		t.Fatalf("preferences did not round trip: %+v", cfg.EQ)
	}
	if !strings.Contains(output.String(), `"restart_required":true`) {
		t.Fatal("missing restart requirement")
	}
}

func TestPreferencesRejectEntireInvalidBatch(t *testing.T) {
	for _, input := range []string{
		`{"buffer_ms":"1000","volume":"NaN"}`, `{"buffer_ms":"1000","mono":"yes"}`,
		`{"buffer_ms":"1000","sample_rate":"12345"}`, `{"buffer_ms":"1000","resample_quality":"1.5"}`,
		`{"buffer_ms":"1000","eq":"[1,2]"}`, `{"buffer_ms":"1000","password":"sensitive-marker"}`,
		`{"buffer_ms":"1000","downloads.directory":"injected\npassword=secret"}`,
		`{"buffer_ms":"1000","plex.libraries":"[\"hello\\nsecret\"]"}`,
	} {
		t.Run(input, func(t *testing.T) {
			dir := t.TempDir()
			t.Setenv("CLIAMP_CONFIG_DIR", dir)
			var output bytes.Buffer
			if err := PreferencesApply(strings.NewReader(input), &output); err == nil {
				t.Fatal("invalid preferences accepted")
			}
			if _, err := os.Stat(filepath.Join(dir, "config.toml")); !os.IsNotExist(err) {
				t.Fatal("invalid batch partially saved")
			}
			if strings.Contains(output.String(), "sensitive-marker") || strings.Contains(output.String(), "injected") {
				t.Fatal("invalid input echoed")
			}
		})
	}
}

func TestPreferenceListsAndEnableFlagsRoundTrip(t *testing.T) {
	t.Setenv("CLIAMP_CONFIG_DIR", t.TempDir())
	var output bytes.Buffer
	if err := PreferencesApply(strings.NewReader(`{"spotify.enabled":"true","tidal.enabled":"false","audiobookshelf.libraries":"[\"Audio, Books\",\"New\"]","plugins.allowed_binaries":"[\"notify-send\"]"}`), &output); err != nil {
		t.Fatal(err)
	}
	output.Reset()
	if err := PreferencesSchema(&output); err != nil {
		t.Fatal(err)
	}
	var response struct {
		Values map[string]string `json:"values"`
	}
	if err := json.Unmarshal(output.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	for key, want := range map[string]string{"spotify.enabled": "true", "tidal.enabled": "false", "audiobookshelf.libraries": `["Audio, Books","New"]`, "plugins.allowed_binaries": `["notify-send"]`} {
		if response.Values[key] != want {
			t.Errorf("%s = %q, want %q", key, response.Values[key], want)
		}
	}
}
