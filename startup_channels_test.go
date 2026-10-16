package main

import "testing"

func TestStartupLiveChannels(t *testing.T) {
	tests := []struct {
		name         string
		positional   []string
		provider     string
		headless     bool
		autoPlay     bool
		skipImplicit bool
		want         bool
	}{
		{name: "tui default", provider: "cliamp"},
		{name: "headless default preloads radio", provider: "cliamp", headless: true, want: true},
		{name: "auto-play preloads radio", provider: "cliamp", autoPlay: true, want: true},
		{name: "desktop skips the implicit preload", provider: "cliamp", headless: true, skipImplicit: true},
		{name: "desktop skip still ignores auto-play preload", provider: "cliamp", autoPlay: true, skipImplicit: true},
		{name: "explicit radio still loads", provider: "radio", headless: true, skipImplicit: true, want: true},
		{name: "radio provider in the tui", provider: "radio", want: true},
		{name: "files replace the preload", positional: []string{"/music/a.flac"}, provider: "cliamp", headless: true},
		{name: "other provider stays empty", provider: "local", headless: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := startupLiveChannels(tt.positional, tt.provider, tt.headless, tt.autoPlay, tt.skipImplicit)
			if got != tt.want {
				t.Fatalf("startupLiveChannels() = %v, want %v", got, tt.want)
			}
		})
	}
}
