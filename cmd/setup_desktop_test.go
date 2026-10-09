package cmd

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestSetupSchemaProvidersAndForms(t *testing.T) {
	var output bytes.Buffer
	if err := SetupSchema("", strings.NewReader("{}"), &output); err != nil {
		t.Fatal(err)
	}
	var listing setupSchema
	if err := json.Unmarshal(output.Bytes(), &listing); err != nil {
		t.Fatal(err)
	}
	if !listing.OK || len(listing.Providers) != len(providers()) {
		t.Fatalf("provider list = %+v", listing)
	}
	for _, spec := range providers() {
		t.Run(spec.key, func(t *testing.T) {
			modes := []string{""}
			if spec.picker != nil {
				for _, option := range spec.picker.options {
					modes = append(modes, option.value)
				}
			}
			for _, mode := range modes {
				values := map[string]string{}
				if mode != "" {
					values[spec.picker.key] = mode
				}
				input, err := json.Marshal(values)
				if err != nil {
					t.Fatal(err)
				}
				output.Reset()
				if err := SetupSchema(spec.key, bytes.NewReader(input), &output); err != nil {
					t.Fatal(err)
				}
				var form setupSchema
				if err := json.Unmarshal(output.Bytes(), &form); err != nil {
					t.Fatal(err)
				}
				if !form.OK || form.Provider != spec.key || form.Name != spec.name {
					t.Fatalf("unexpected form identity: %+v", form)
				}
				if spec.picker != nil {
					want := mode
					if want == "" {
						want = spec.picker.options[0].value
					}
					if form.Values[spec.picker.key] != want {
						t.Fatalf("picker = %q, want %q", form.Values[spec.picker.key], want)
					}
				}
				var wantKeys, gotKeys []string
				for _, field := range spec.fields {
					if field.onlyIf == nil || field.onlyIf(form.Values) {
						wantKeys = append(wantKeys, field.key)
					}
				}
				for _, field := range form.Fields {
					gotKeys = append(gotKeys, field.Key)
				}
				if !slices.Equal(gotKeys, wantKeys) {
					t.Errorf("mode %q fields = %v, want %v", mode, gotKeys, wantKeys)
				}
			}
		})
	}
}

func TestSetupSchemaNeverReturnsCredentials(t *testing.T) {
	t.Setenv("CLIAMP_CONFIG_DIR", t.TempDir())
	var output bytes.Buffer
	if err := SetupApply("ytmusic", strings.NewReader(`{"_mode":"custom","client_id":"app","client_secret":"stored-secret"}`), &output, true); err != nil {
		t.Fatal(err)
	}
	for _, input := range []string{`{}`, `{"_mode":"custom","client_secret":"submitted-secret"}`} {
		output.Reset()
		if err := SetupSchema("ytmusic", strings.NewReader(input), &output); err != nil {
			t.Fatal(err)
		}
		if strings.Contains(output.String(), "stored-secret") || strings.Contains(output.String(), "submitted-secret") {
			t.Fatal("schema returned credentials")
		}
		var form setupSchema
		if err := json.Unmarshal(output.Bytes(), &form); err != nil {
			t.Fatal(err)
		}
		if _, ok := form.Values["client_secret"]; ok {
			t.Fatal("secret is present in schema values")
		}
	}
}

func TestSetupInputAndProviderValidation(t *testing.T) {
	tests := []struct {
		name, provider, input string
	}{
		{"unknown provider", "unrecognized-private-value", `{}`},
		{"unknown field", "spotify", `{"private-value":"secret"}`},
		{"invalid picker", "qobuz", `{"_qobuz_quality":"secret"}`},
		{"non-object", "qobuz", `"secret"`},
		{"null object", "qobuz", `null`},
		{"null field", "qobuz", `{"_qobuz_quality":null}`},
		{"number field", "qobuz", `{"_qobuz_quality":6}`},
		{"malformed", "qobuz", `{"secret"`},
		{"two objects", "qobuz", `{} {"secret":"value"}`},
		{"over limit", "qobuz", strings.Repeat(" ", setupInputLimit+1)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, run := range []func(string, io.Reader, io.Writer) error{SetupSchema, func(provider string, input io.Reader, output io.Writer) error {
				return SetupApply(provider, input, output, true)
			}} {
				var output bytes.Buffer
				err := run(tt.provider, strings.NewReader(tt.input), &output)
				if err == nil || !strings.Contains(output.String(), `"ok":false`) {
					t.Fatalf("error = %v, output = %s", err, output.String())
				}
				if strings.Contains(output.String(), "secret") || strings.Contains(err.Error(), "private-value") {
					t.Fatal("invalid input was echoed in diagnostic")
				}
			}
		})
	}
}

func TestSetupApplyPreservesUnrelatedConfig(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("CLIAMP_CONFIG_DIR", dir)
	path := filepath.Join(dir, "config.toml")
	initial := "volume = -5\n\n[ytmusic]\n# Keep this comment\nenabled = true\nclient_id = \"old\"\nclient_secret = \"old-secret\"\nexpand_playlist = false\n\n[navidrome]\nurl = \"https://music.example\"\n"
	if err := os.WriteFile(path, []byte(initial), 0o600); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := SetupApply("ytmusic", strings.NewReader(`{"_mode":"off"}`), &output, true); err != nil {
		t.Fatal(err)
	}
	if got := output.String(); got != "{\"ok\":true,\"restart_required\":true}\n" {
		t.Fatalf("result = %s", got)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	want := "volume = -5\n\n[ytmusic]\n# Keep this comment\nenabled = false\nexpand_playlist = false\n\n[navidrome]\nurl = \"https://music.example\"\n"
	if string(data) != want {
		t.Fatalf("config = %s, want %s", data, want)
	}
}

func TestSetupApplyDefaultsAndRequiredValidation(t *testing.T) {
	for _, tt := range []struct {
		name, provider, input, want string
		wantErr                     bool
	}{
		{"picker default", "qobuz", `{}`, "quality = 6", false},
		{"field default", "spotify", `{"_spotify_mode":"default"}`, "bitrate = 320", false},
		{"required", "navidrome", `{}`, "", true},
		{"field limit", "mixcloud", `{"max_items":"0"}`, "", true},
		{"extra validation", "spotify", `{"_spotify_mode":"default","bitrate":"secret"}`, "", true},
		{"URL", "navidrome", `{"url":"invalid-secret","user":"u","password":"p"}`, "", true},
		{"unset reference", "navidrome", `{"url":"https://music.example","user":"u","password":"$CLIAMP_TEST_MISSING_SECRET"}`, "", true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			t.Setenv("CLIAMP_CONFIG_DIR", dir)
			t.Setenv("CLIAMP_TEST_MISSING_SECRET", "")
			var output bytes.Buffer
			err := SetupApply(tt.provider, strings.NewReader(tt.input), &output, true)
			if (err != nil) != tt.wantErr {
				t.Fatalf("apply error = %v", err)
			}
			data, readErr := os.ReadFile(filepath.Join(dir, "config.toml"))
			if tt.wantErr {
				if !os.IsNotExist(readErr) {
					t.Fatal("invalid setup created configuration")
				}
				if strings.Contains(output.String(), "secret") {
					t.Fatal("invalid values were echoed")
				}
			} else if readErr != nil || !strings.Contains(string(data), tt.want) {
				t.Fatalf("config = %s, error = %v", data, readErr)
			}
		})
	}
}

func TestSetupApplyProbeAndEnvironmentReferences(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("CLIAMP_CONFIG_DIR", dir)
	t.Setenv("CLIAMP_TEST_SETUP_BROWSER", "firefox:profile")
	var spec providerSpec
	for _, provider := range providers() {
		if provider.key == "netease" {
			spec = provider
		}
	}
	probed := false
	spec.validate = func(values map[string]string) error {
		probed = true
		if values["cookies_from"] != "firefox:profile" {
			t.Fatalf("probe received unresolved environment reference")
		}
		values["cookies_from"] = "firefox:profile"
		values["user_id"] = "42"
		return nil
	}
	if err := applySetupValues(spec, map[string]string{keyNetEaseBrowser: "custom", "cookies_from": "$CLIAMP_TEST_SETUP_BROWSER"}, true); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "config.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if !probed || !strings.Contains(string(data), `cookies_from = "$CLIAMP_TEST_SETUP_BROWSER"`) || !strings.Contains(string(data), `user_id = "42"`) {
		t.Fatalf("probe result was not saved: %s", data)
	}
}

func TestSetupApplyFailedProbeDoesNotSaveOrExposeErrors(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("CLIAMP_CONFIG_DIR", dir)
	spec := providers()[0]
	spec.validate = func(map[string]string) error {
		return errors.New("request to https://user:private-password@music.example failed")
	}
	err := applySetupValues(spec, map[string]string{"url": "https://music.example", "user": "user", "password": "private-password"}, true)
	if err == nil || strings.Contains(err.Error(), "private-password") {
		t.Fatalf("probe error was not sanitized: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "config.toml")); !os.IsNotExist(err) {
		t.Fatal("failed validation created configuration")
	}
}

func TestSetupApplySwitchingAuthRemovesHiddenCredentials(t *testing.T) {
	t.Setenv("CLIAMP_CONFIG_DIR", t.TempDir())
	for _, spec := range providers() {
		if spec.key != "emby" {
			continue
		}
		spec.validate = func(values map[string]string) error {
			if values["token"] != "" || values["user"] != "user" || values["password"] != "password" {
				t.Fatal("probe received credentials from the wrong authentication mode")
			}
			return nil
		}
		if err := applySetupValues(spec, map[string]string{
			keyEmbyAuth: "password", "url": "https://music.example/", "token": "stale-token", "user": "user", "password": "password",
		}, true); err != nil {
			t.Fatal(err)
		}
		return
	}
	t.Fatal("Emby provider was not found")
}

func TestSetupApplyWithoutConnectionCheckStillValidatesForm(t *testing.T) {
	for _, tt := range []struct {
		name    string
		values  map[string]string
		wantErr bool
	}{
		{"valid", map[string]string{"url": "https://music.example", "user": "u", "password": "p"}, false},
		{"missing password", map[string]string{"url": "https://music.example", "user": "u"}, true},
		{"invalid URL", map[string]string{"url": "invalid", "user": "u", "password": "p"}, true},
		{"unset environment", map[string]string{"url": "https://music.example", "user": "u", "password": "$CLIAMP_TEST_EMPTY_PASSWORD"}, true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			t.Setenv("CLIAMP_CONFIG_DIR", dir)
			t.Setenv("CLIAMP_TEST_EMPTY_PASSWORD", "")
			spec := providers()[0]
			spec.validate = func(map[string]string) error {
				t.Fatal("offline save performed a connection check")
				return nil
			}
			err := applySetupValues(spec, tt.values, false)
			if (err != nil) != tt.wantErr {
				t.Fatalf("offline save error = %v", err)
			}
			_, statErr := os.Stat(filepath.Join(dir, "config.toml"))
			if tt.wantErr && !os.IsNotExist(statErr) {
				t.Fatal("invalid offline setup created configuration")
			}
			if !tt.wantErr && statErr != nil {
				t.Fatal(statErr)
			}
		})
	}
}

func TestSetupTidalCustomOAuthCredentials(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("CLIAMP_CONFIG_DIR", dir)
	var output bytes.Buffer
	if err := SetupApply("tidal", strings.NewReader(`{"_tidal_quality":"hires","client_id":"custom-id","client_secret":"private-tidal-secret"}`), &output, true); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "config.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `client_secret = "private-tidal-secret"`) || !strings.Contains(string(data), `quality = "hires"`) {
		t.Fatal("Tidal OAuth override not saved")
	}
	output.Reset()
	if err := SetupSchema("tidal", strings.NewReader(`{}`), &output); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(output.String(), "private-tidal-secret") {
		t.Fatal("Tidal schema exposed credentials")
	}
}
