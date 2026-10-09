package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestDesktopProviderSetupCommands(t *testing.T) {
	t.Setenv("CLIAMP_CONFIG_DIR", t.TempDir())
	for _, tt := range []struct {
		name, input string
		args        []string
		wantErr     bool
	}{
		{"list", `{}`, []string{"setup", "schema"}, false},
		{"schema", `{"_spotify_mode":"default"}`, []string{"setup", "schema", "--provider", "spotify"}, false},
		{"apply", `{"_qobuz_quality":"27"}`, []string{"setup", "apply", "--provider", "qobuz"}, false},
		{"offline apply", `{"url":"https://offline.invalid","user":"user","password":"password"}`, []string{"setup", "apply", "--provider", "navidrome", "--save-without-check"}, false},
		{"missing provider", `{}`, []string{"setup", "apply"}, true},
		{"invalid fields", `{"client_id":"private-desktop-test-value","client_secret":"private-desktop-test-value"}`, []string{"setup", "apply", "--provider", "qobuz"}, true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			app := buildApp()
			app.Reader = strings.NewReader(tt.input)
			var output bytes.Buffer
			app.Writer = &output
			err := app.Run(t.Context(), append([]string{"cliamp"}, tt.args...))
			if (err != nil) != tt.wantErr {
				t.Fatalf("Run error = %v", err)
			}
			var result struct {
				OK              bool   `json:"ok"`
				Provider        string `json:"provider"`
				RestartRequired bool   `json:"restart_required"`
			}
			if err := json.Unmarshal(output.Bytes(), &result); err != nil {
				t.Fatalf("JSON response = %s, error = %v", output.Bytes(), err)
			}
			if result.OK == tt.wantErr {
				t.Fatalf("result = %+v", result)
			}
			if tt.name == "apply" && !result.RestartRequired {
				t.Fatal("apply did not request engine restart")
			}
			if tt.name == "schema" && result.Provider != "spotify" {
				t.Fatal("schema did not honor --provider")
			}
			if strings.Contains(output.String(), "private-desktop-test-value") {
				t.Fatal("setup command leaked input values")
			}
		})
	}
}
