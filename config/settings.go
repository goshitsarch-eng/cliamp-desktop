package config

import (
	"errors"
	"strings"
)

// Setting is one validated preference update. Value is encoded TOML, and an
// empty Section selects a top-level preference.
type Setting struct {
	Section, Key, Value string
}

// SaveSettings applies a batch under the existing cross-process config lock.
// It preserves unknown settings and comments like the individual savers do.
func SaveSettings(settings []Setting) error {
	for _, setting := range settings {
		if !validTOMLKey(setting.Key) || (setting.Section != "" && !validTOMLSection(setting.Section)) || hasDisallowedTOMLControl(setting.Value) {
			return errors.New("invalid preference setting")
		}
	}
	if len(settings) == 0 {
		return nil
	}
	return update(func(data string) string {
		for _, setting := range settings {
			if setting.Section == "" {
				data = editTopLevel(data, setting.Key, setting.Key+" = "+setting.Value)
			} else {
				data = editSection(data, setting.Section, []KeyValue{{Key: setting.Key, Value: setting.Value}}, nil)
			}
		}
		return data
	})
}

func validTOMLKey(key string) bool {
	if key == "" {
		return false
	}
	for i := range len(key) {
		c := key[i]
		if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

func validTOMLSection(section string) bool {
	for part := range strings.SplitSeq(section, ".") {
		if !validTOMLKey(part) {
			return false
		}
	}
	return true
}

func hasDisallowedTOMLControl(value string) bool {
	for i := range len(value) {
		c := value[i]
		if (c < 0x20 && c != '\t') || c == 0x7f {
			return true
		}
	}
	return false
}
