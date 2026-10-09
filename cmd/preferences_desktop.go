package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"reflect"
	"slices"
	"strconv"
	"strings"

	"github.com/bjarneo/cliamp/config"
	"github.com/bjarneo/cliamp/external/mixcloud"
)

type preferenceField struct {
	Key     string   `json:"key"`
	Label   string   `json:"label"`
	Group   string   `json:"group"`
	Type    string   `json:"type"`
	Value   string   `json:"value"`
	Help    string   `json:"help"`
	Options []string `json:"options,omitempty"`
	Min     *float64 `json:"min,omitempty"`
	Max     *float64 `json:"max,omitempty"`
	path    string
}

// PreferencesSchema returns only explicitly listed, nonsecret preferences.
// Account passwords, tokens, plugin credentials and saved OAuth data are never
// included. Provider connection forms remain available through setup schema.
func PreferencesSchema(output io.Writer) error {
	cfg, err := config.Load()
	if err != nil {
		return writeSetupError(output, errors.New("could not read preferences"))
	}
	fields := preferenceFields()
	values := make(map[string]string, len(fields))
	for i := range fields {
		fields[i].Value = preferenceValue(cfg, fields[i])
		values[fields[i].Key] = fields[i].Value
	}
	return json.NewEncoder(output).Encode(struct {
		OK     bool              `json:"ok"`
		Fields []preferenceField `json:"fields"`
		Values map[string]string `json:"values"`
	}{true, fields, values})
}

// PreferencesApply checks the complete change before atomically saving it.
// The desktop restarts its owned engine to load settings with startup effects.
func PreferencesApply(input io.Reader, output io.Writer) error {
	values, err := readSetupValues(input)
	if err != nil {
		return writeSetupError(output, err)
	}
	known := make(map[string]preferenceField)
	for _, field := range preferenceFields() {
		known[field.Key] = field
	}
	var settings []config.Setting
	for key, value := range values {
		field, ok := known[key]
		if !ok {
			return writeSetupError(output, errors.New("unknown preference"))
		}
		encoded, err := encodePreference(field, value)
		if err != nil {
			return writeSetupError(output, fmt.Errorf("%s: %w", field.Label, err))
		}
		section, name := "", key
		if before, after, ok := strings.Cut(key, "."); ok {
			section, name = before, after
		}
		settings = append(settings, config.Setting{Section: section, Key: name, Value: encoded})
	}
	// Stable ordering makes new configuration files and reviews predictable.
	slices.SortFunc(settings, func(a, b config.Setting) int {
		return strings.Compare(a.Section+"."+a.Key, b.Section+"."+b.Key)
	})
	if err := config.SaveSettings(settings); err != nil {
		return writeSetupError(output, errors.New("could not save preferences"))
	}
	return json.NewEncoder(output).Encode(map[string]any{"ok": true, "restart_required": len(settings) > 0})
}

func preferenceFields() []preferenceField {
	var fields []preferenceField
	add := func(key, path, group, kind string) {
		label := key
		if _, tail, ok := strings.Cut(key, "."); ok {
			label = tail
		}
		label = strings.ReplaceAll(label, "_", " ")
		label = strings.ToUpper(label[:1]) + label[1:]
		fields = append(fields, preferenceField{Key: key, path: path, Group: group, Type: kind, Label: label})
	}
	for _, item := range []struct{ key, path, group, kind string }{
		{"volume", "Volume", "Playback", "number"}, {"volume_min", "VolumeMin", "Playback", "number"},
		{"repeat", "Repeat", "Playback", "string"}, {"shuffle", "Shuffle", "Playback", "bool"},
		{"mono", "Mono", "Playback", "bool"}, {"speed", "Speed", "Playback", "number"},
		{"auto_play", "AutoPlay", "Playback", "bool"}, {"seek_large_step_sec", "SeekStepLarge", "Playback", "integer"},
		{"lyrics_offset_ms", "LyricsOffsetMs", "Playback", "integer"}, {"provider", "Provider", "Startup", "string"},
		{"initial_directory", "InitialDirectory", "Startup", "string"}, {"downloads.directory", "Downloads.Directory", "Files", "string"},
		{"sample_rate", "SampleRate", "Audio", "integer"}, {"buffer_ms", "BufferMs", "Audio", "integer"},
		{"resample_quality", "ResampleQuality", "Audio", "integer"}, {"bit_depth", "BitDepth", "Audio", "integer"},
		{"audio_device", "AudioDevice", "Audio", "string"}, {"eq_preset", "EQPreset", "Audio", "string"},
		{"eq", "EQ", "Audio", "equalizer"}, {"theme", "Theme", "Appearance", "string"},
		{"visualizer", "Visualizer", "Appearance", "string"}, {"vis_rows", "VisRows", "Terminal appearance", "integer"},
		{"vis_volume_linked", "VisVolumeLinked", "Appearance", "bool"}, {"simplified", "Simplified", "Terminal appearance", "bool"},
		{"hide_help_bar", "HideHelpBar", "Terminal appearance", "bool"}, {"hide_settings_pane", "HideSettingsPane", "Terminal appearance", "bool"},
		{"show_metadata", "ShowMetadata", "Terminal appearance", "bool"}, {"expanded", "Expanded", "Terminal appearance", "bool"},
		{"padding_horizontal", "PaddingH", "Terminal appearance", "integer"}, {"padding_vertical", "PaddingV", "Terminal appearance", "integer"},
		{"log_level", "LogLevel", "System", "string"}, {"low_power", "LowPower", "System", "bool"},
		{"plugins.disabled", "", "Plugins", "list"}, {"plugins.allowed_binaries", "", "Plugins", "list"},
		{"radio.country", "Radio.Country", "Radio", "string"}, {"podcast.country", "Podcast.Country", "Podcasts", "string"},
		{"navidrome.browse_sort", "Navidrome.BrowseSort", "Navidrome", "string"}, {"navidrome.format", "Navidrome.Format", "Navidrome", "string"},
		{"navidrome.scrobble", "Navidrome.ScrobbleDisabled", "Navidrome", "bool"}, {"lyrion.show_unplayable", "Lyrion.ShowUnplayable", "Lyrion", "bool"},
		{"spotify.enabled", "Spotify.Enabled", "Spotify", "bool"}, {"spotify.client_id", "Spotify.ClientID", "Spotify", "string"}, {"spotify.bitrate", "Spotify.Bitrate", "Spotify", "integer"},
		{"qobuz.enabled", "Qobuz.Enabled", "Qobuz", "bool"}, {"qobuz.quality", "Qobuz.Quality", "Qobuz", "integer"},
		{"tidal.enabled", "Tidal.Enabled", "Tidal", "bool"}, {"tidal.client_id", "Tidal.ClientID", "Tidal", "string"}, {"tidal.quality", "Tidal.Quality", "Tidal", "string"},
		{"ytmusic.enabled", "YouTubeMusic.Enabled", "YouTube", "bool"}, {"ytmusic.client_id", "YouTubeMusic.ClientID", "YouTube", "string"},
		{"ytmusic.cookies_from", "YouTubeMusic.CookiesFrom", "YouTube", "string"}, {"ytmusic.expand_playlist", "YouTubeMusic.ExpandPlaylist", "YouTube", "bool"},
		{"soundcloud.enabled", "SoundCloud.Enabled", "SoundCloud", "bool"}, {"soundcloud.user", "SoundCloud.User", "SoundCloud", "string"}, {"soundcloud.cookies_from", "SoundCloud.CookiesFrom", "SoundCloud", "string"},
		{"mixcloud.enabled", "Mixcloud.Enabled", "Mixcloud", "bool"}, {"mixcloud.username", "Mixcloud.Username", "Mixcloud", "string"}, {"mixcloud.cookies_from", "Mixcloud.CookiesFrom", "Mixcloud", "string"},
		{"mixcloud.styles", "Mixcloud.Styles", "Mixcloud", "list"}, {"mixcloud.max_items", "Mixcloud.MaxItems", "Mixcloud", "integer"}, {"mixcloud.stream_creators", "Mixcloud.StreamCreators", "Mixcloud", "integer"},
		{"netease.enabled", "NetEase.Enabled", "NetEase", "bool"}, {"netease.cookies_from", "NetEase.CookiesFrom", "NetEase", "string"}, {"netease.user_id", "NetEase.UserID", "NetEase", "string"},
		{"yandex.enabled", "Yandex.Enabled", "Yandex", "bool"}, {"plex.libraries", "Plex.Libraries", "Plex", "list"},
		{"jellyfin.user_id", "Jellyfin.UserID", "Jellyfin", "string"}, {"emby.user_id", "Emby.UserID", "Emby", "string"}, {"audiobookshelf.libraries", "Audiobookshelf.Libraries", "Audiobookshelf", "list"},
	} {
		add(item.key, item.path, item.group, item.kind)
	}
	options := map[string][]string{
		"repeat": {"off", "all", "one"}, "log_level": {"debug", "info", "warn", "error"},
		"sample_rate": {"0", "22050", "44100", "48000", "96000", "192000"}, "bit_depth": {"16", "32"},
		"spotify.bitrate": {"96", "160", "320"}, "qobuz.quality": {"5", "6", "7", "27"},
		"tidal.quality": {"", "low", "high", "lossless", "hires"},
	}
	ranges := map[string][2]float64{
		"volume": {-90, 6}, "volume_min": {-90, 0}, "speed": {0.25, 2}, "seek_large_step_sec": {6, 600},
		"lyrics_offset_ms": {-10000, 10000}, "buffer_ms": {50, 5000}, "resample_quality": {1, 4},
		"vis_rows": {0, 40}, "padding_horizontal": {0, 10}, "padding_vertical": {0, 5},
		"mixcloud.max_items": {0, mixcloud.MaxItemsLimit}, "mixcloud.stream_creators": {0, mixcloud.MaxStreamCreators},
	}
	for i := range fields {
		field := &fields[i]
		field.Options = options[field.Key]
		if bounds, ok := ranges[field.Key]; ok {
			field.Min, field.Max = &bounds[0], &bounds[1]
		}
		switch field.Type {
		case "list":
			field.Help = "JSON array of names, for example [\"First\", \"Second\"]."
		case "equalizer":
			field.Help = "Ten gains from -12 to 12 dB, in a JSON array."
		}
		if field.Key == "sample_rate" {
			field.Help = "0 automatically detects the output device sample rate."
		}
		if field.Key == "audio_device" {
			field.Help = "Output device name; blank uses the system default. Windows uses the system output."
		}
	}
	return fields
}

func preferenceValue(cfg config.Config, field preferenceField) string {
	if strings.HasPrefix(field.Key, "plugins.") {
		names := []string{}
		for _, name := range strings.Split(cfg.Plugins[""][strings.TrimPrefix(field.Key, "plugins.")], ",") {
			if strings.TrimSpace(name) != "" {
				names = append(names, strings.TrimSpace(name))
			}
		}
		data, _ := json.Marshal(names)
		return string(data)
	}
	var enabled *bool
	switch field.Key {
	case "spotify.enabled":
		v := cfg.Spotify.IsSet()
		enabled = &v
	case "qobuz.enabled":
		v := cfg.Qobuz.IsSet()
		enabled = &v
	case "tidal.enabled":
		v := cfg.Tidal.IsSet()
		enabled = &v
	case "ytmusic.enabled":
		v := cfg.YouTubeMusic.IsSet()
		enabled = &v
	case "navidrome.scrobble":
		v := !cfg.Navidrome.ScrobbleDisabled
		enabled = &v
	}
	if enabled != nil {
		return strconv.FormatBool(*enabled)
	}
	v := reflect.ValueOf(cfg)
	for _, part := range strings.Split(field.path, ".") {
		v = v.FieldByName(part)
	}
	if v.Kind() == reflect.Pointer {
		if v.IsNil() {
			return "true"
		}
		v = v.Elem()
	}
	switch v.Kind() {
	case reflect.String:
		return v.String()
	case reflect.Bool:
		return strconv.FormatBool(v.Bool())
	case reflect.Int:
		return strconv.FormatInt(v.Int(), 10)
	case reflect.Float64:
		return strconv.FormatFloat(v.Float(), 'f', -1, 64)
	default:
		if v.Kind() == reflect.Slice && v.IsNil() {
			return "[]"
		}
		data, _ := json.Marshal(v.Interface())
		return string(data)
	}
}

func encodePreference(field preferenceField, value string) (string, error) {
	if strings.ContainsAny(value, "\r\n\x00") {
		return "", errors.New("use a single-line value")
	}
	if len(field.Options) > 0 && !slices.Contains(field.Options, value) {
		return "", errors.New("choose a supported option")
	}
	switch field.Type {
	case "bool":
		if value != "true" && value != "false" {
			return "", errors.New("must be true or false")
		}
		return value, nil
	case "number", "integer":
		n, err := strconv.ParseFloat(value, 64)
		if err != nil || math.IsInf(n, 0) || math.IsNaN(n) || (field.Type == "integer" && math.Trunc(n) != n) {
			return "", errors.New("must be a finite number of the expected type")
		}
		if (field.Min != nil && n < *field.Min) || (field.Max != nil && n > *field.Max) {
			return "", errors.New("outside the supported range")
		}
		return strconv.FormatFloat(n, 'f', -1, 64), nil
	case "equalizer":
		var bands []float64
		if json.Unmarshal([]byte(value), &bands) != nil || len(bands) != 10 {
			return "", errors.New("provide ten equalizer gains")
		}
		for _, gain := range bands {
			if gain < -12 || gain > 12 {
				return "", errors.New("equalizer gains must be between -12 and 12")
			}
		}
		data, _ := json.Marshal(bands)
		return string(data), nil
	case "list":
		var names []string
		if json.Unmarshal([]byte(value), &names) != nil || names == nil {
			return "", errors.New("provide a JSON array of names")
		}
		encoded := make([]string, len(names))
		for i, name := range names {
			if strings.ContainsAny(name, "\r\n\x00") {
				return "", errors.New("names must be single-line")
			}
			encoded[i] = config.QuoteString(name)
		}
		return "[" + strings.Join(encoded, ", ") + "]", nil
	default:
		return config.QuoteString(value), nil
	}
}
