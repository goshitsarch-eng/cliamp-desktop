package luaplugin

import (
	"encoding/json"

	lua "github.com/yuin/gopher-lua"
)

// registerJSONAPI adds cliamp.json.{encode,decode} to the cliamp table.
func registerJSONAPI(L *lua.LState, cliamp *lua.LTable) {
	tbl := L.NewTable()

	// cliamp.json.decode(str) -> table
	L.SetField(tbl, "decode", L.NewFunction(func(L *lua.LState) int {
		str := L.CheckString(1)
		var v any
		if err := json.Unmarshal([]byte(str), &v); err != nil {
			return pushErr(L, err.Error())
		}
		L.Push(toLua(L, v))
		return 1
	}))

	// cliamp.json.encode(table) -> string
	L.SetField(tbl, "encode", L.NewFunction(func(L *lua.LState) int {
		val := L.Get(1)
		nodes := 0
		goVal := luaToGoValue(val, nil, 0, &nodes)
		if nodes > maxLuaConvertNodes {
			return pushErr(L, "table exceeds maximum size")
		}
		data, err := json.Marshal(goVal)
		if err != nil {
			return pushErr(L, err.Error())
		}
		L.Push(lua.LString(string(data)))
		return 1
	}))

	L.SetField(cliamp, "json", tbl)
}

// maxLuaConvertDepth bounds table nesting accepted by luaToGo. Lua can build a
// deeply nested table cheaply, and unbounded recursion here would overflow the
// Go stack — a fatal error the plugin sandbox cannot contain.
const (
	maxLuaConvertDepth = 64
	maxLuaConvertNodes = 100_000
)

func luaToGo(val lua.LValue) any {
	nodes := 0
	return luaToGoValue(val, nil, 0, &nodes)
}

// luaToGoValue converts val to its Go equivalent. Tables already being
// converted on the current path (cycles), tables nested deeper than
// maxLuaConvertDepth, and nodes beyond maxLuaConvertNodes become nil instead of
// recursing forever or exhausting memory on shared-reference DAGs.
func luaToGoValue(val lua.LValue, path map[*lua.LTable]struct{}, depth int, nodes *int) any {
	*nodes++
	if *nodes > maxLuaConvertNodes {
		return nil
	}
	switch v := val.(type) {
	case *lua.LNilType:
		return nil
	case lua.LBool:
		return bool(v)
	case lua.LNumber:
		return float64(v)
	case lua.LString:
		return string(v)
	case *lua.LTable:
		if depth >= maxLuaConvertDepth {
			return nil
		}
		if _, cyclic := path[v]; cyclic {
			return nil
		}
		if path == nil {
			path = make(map[*lua.LTable]struct{})
		}
		// Tracking only the active path keeps repeated sibling references
		// (a DAG) convertible while still catching true cycles.
		path[v] = struct{}{}
		defer delete(path, v)

		// Detect if it's an array (sequential integer keys starting at 1).
		maxN := v.MaxN()
		if maxN > 0 {
			if maxN > maxLuaConvertNodes-*nodes {
				maxN = max(0, maxLuaConvertNodes-*nodes)
			}
			arr := make([]any, 0, maxN)
			for i := 1; i <= maxN; i++ {
				if *nodes > maxLuaConvertNodes {
					break
				}
				arr = append(arr, luaToGoValue(v.RawGetInt(i), path, depth+1, nodes))
			}
			return arr
		}
		m := make(map[string]any)
		v.ForEach(func(key, value lua.LValue) {
			if *nodes > maxLuaConvertNodes {
				return
			}
			if ks, ok := key.(lua.LString); ok {
				m[string(ks)] = luaToGoValue(value, path, depth+1, nodes)
			}
		})
		return m
	default:
		return nil
	}
}
