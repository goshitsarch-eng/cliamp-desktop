package cmd

import (
	"errors"
	"strings"

	"github.com/bjarneo/cliamp/config"
)

// Both setup frontends share these opt-in providers.
func additionalDesktopProviders() []providerSpec {
	return []providerSpec{
		{
			key: "soundcloud", name: "SoundCloud", section: "soundcloud",
			intro: []string{"Search and public playback use yt-dlp. A profile name adds Tracks, Likes, and Reposts; browser cookies enable signed-in playback."},
			fields: []fieldSpec{
				{key: "user", label: "Profile name", help: "Optional SoundCloud profile name"},
				{key: "cookies_from", label: "Browser cookies", help: "Optional: firefox, chrome, brave, or another yt-dlp browser"},
			},
			owned: []string{"enabled", "user", "cookies_from"},
			extraValidate: func(v map[string]string) error {
				if strings.ContainsAny(v["cookies_from"], "\r\n") {
					return errors.New("browser source must be a single line")
				}
				return nil
			},
			body: func(v map[string]string) []config.KeyValue {
				return []config.KeyValue{rawKV("enabled", "true"), quotedKV("user", v["user"]), quotedKV("cookies_from", v["cookies_from"])}
			},
		},
		{
			key: "yandex", name: "Yandex Music", section: "yandex",
			intro:  []string{"Enter your personal Yandex Music OAuth token. A Music Plus subscription is needed for full tracks.", "Get a token: https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d"},
			fields: []fieldSpec{{key: "token", label: "Personal OAuth token", required: true, secret: true}},
			owned:  []string{"enabled", "token"},
			extraValidate: func(v map[string]string) error {
				if strings.ContainsAny(v["token"], "\r\n\t ") {
					return errors.New("enter the token only, without whitespace")
				}
				return nil
			},
			body: func(v map[string]string) []config.KeyValue {
				return []config.KeyValue{rawKV("enabled", "true"), quotedKV("token", v["token"])}
			},
		},
	}
}
