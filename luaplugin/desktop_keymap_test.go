package luaplugin

import "testing"

func TestDesktopKeyBindingsIncludeUndescribedAndCleanup(t *testing.T) {
	m := newTestManager()
	p := loadTestPlugin(t, m, "desktop-keys", `
 local p=plugin.register({name="Desktop Keys",type="hook",permissions={"keymap"}})
 p:bind("ctrl+alt+j",function()end)
 p:bind("ctrl+alt+k","Do something",function()end)
 `)
	if p == nil {
		t.Fatal("plugin failed to load")
	}
	bindings := m.DesktopKeyBindings()
	if len(bindings) != 2 || bindings[0].Key != "ctrl+alt+j" || bindings[0].Description != "" || bindings[1].Description != "Do something" {
		t.Fatalf("bindings: %+v", bindings)
	}
	if len(m.KeyBindings()) != 1 {
		t.Fatal("terminal keymap semantics changed")
	}
	m.cleanupPlugin(p)
	if len(m.DesktopKeyBindings()) != 0 {
		t.Fatal("unloaded plugin bindings retained")
	}
}
