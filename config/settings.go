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
		if setting.Key == "" || strings.ContainsAny(setting.Section, "\r\n[]") || strings.ContainsAny(setting.Key, "\r\n=[]") || strings.ContainsAny(setting.Value, "\r\n") {
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
