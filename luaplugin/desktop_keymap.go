package luaplugin

import "sort"

// DesktopKeyBinding includes unnamed key callbacks as well as actions shown
// in the terminal keymap. The desktop can dispatch every registered callback.
type DesktopKeyBinding struct {
	Key         string `json:"key"`
	Plugin      string `json:"plugin"`
	Description string `json:"description,omitempty"`
}

func (m *Manager) DesktopKeyBindings() []DesktopKeyBinding {
	m.mu.RLock()
	defer m.mu.RUnlock()
	result := make([]DesktopKeyBinding, 0, len(m.keyBinds))
	for key, hooks := range m.keyBinds {
		for _, h := range hooks {
			result = append(result, DesktopKeyBinding{
				Key:         key,
				Plugin:      h.plugin.Name,
				Description: h.desc,
			})
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Key == result[j].Key {
			return result[i].Plugin < result[j].Plugin
		}
		return result[i].Key < result[j].Key
	})
	return result
}
