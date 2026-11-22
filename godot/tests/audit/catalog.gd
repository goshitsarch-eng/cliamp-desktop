extends AuditKit
## Public browse routes and an isolated RSS subscription, served by the audit runner.

func run() -> void:
	await click_name("Providers")
	await wait(0.5)
	var browser: ProviderBrowser = find_all(func(c: Control) -> bool: return c is ProviderBrowser)[0]
	for provider_name in ["Podcasts", "Radio"]:
		var provider := by_name("Provider") as OptionButton
		await click(provider)
		for index in provider.item_count:
			if provider.get_item_text(index) == provider_name:
				await pick_item(provider.get_popup(), index)
				break
		await settle(browser)
		check(provider.text == provider_name, "selected catalog " + provider_name)
		var routes := ProviderBrowse.routes(browser._browse, browser._provider)
		for route in routes:
			var label: String = route["label"]
			await click(by_name(label, browser))
			await settle(browser)
			if route["mode"] == "location":
				var test_zone := OS.get_environment("CLIAMP_QA_RADIO_TIMEZONE")
				var choice := "Do not use location" if test_zone.is_empty() else "Allow location"
				for action in ["Cancel", choice]:
					for i in 80:
						if not dialogs().is_empty() and dialogs().back().title == "Local radio":
							break
						await wait(0.1)
					var button: Button
					if not dialogs().is_empty():
						var consent: ConfirmationDialog = dialogs().back()
						for child in consent.get_ok_button().get_parent().get_children(true):
							if child is Button and child.text == action:
								button = child
					if button == null:
						check(false, "local radio consent shows " + action)
						break
					await click(button)
					for i in 50:
						if dialogs().is_empty():
							break
						await wait(0.1)
					await settle(browser)
					if action == "Cancel":
						await click(by_name(label, browser))
				if not test_zone.is_empty():
					var location := await Backend.call_op("provider.location", {"provider": "radio"})
					check(not Backend.failed(location) and not Util.object(location.get("location")).get("needed", true), "radio consent is saved for the test timezone")
					if test_zone == "Europe/Oslo":
						var config_path := OS.get_environment("CLIAMP_CONFIG_DIR").path_join("config.toml")
						check(FileAccess.get_file_as_string(config_path).contains('country = "NO"'), "Oslo test timezone saves Norway")
				continue
			print("browse ", provider_name, " / ", label, " items ", browser._items.size(), " error ", browser._error)
			var sorts := by_name("Sort", browser) as OptionButton
			if sorts != null:
				var count := sorts.item_count
				for i in count:
					sorts = by_name("Sort", browser)
					await click(sorts)
					await pick_item(sorts.get_popup(), i)
					await settle(browser)
			var pins := find_all(func(c: Control) -> bool: return c is Button and c.accessibility_name.begins_with("Pin "), browser)
			if not pins.is_empty():
				var name: String = pins[0].accessibility_name.trim_prefix("Pin ")
				await click(pins[0])
				await settle(browser)
				await click(by_name("Pinned only", browser))
				await click(by_name("Unpin " + name, browser))
				await settle(browser)
				await click(by_name("Pinned only", browser))
			if route["mode"] == "subscriptions":
				var menu := by_name("Episode actions", browser) as MenuButton
				if menu == null:
					check(false, "fixture subscription has an episode menu")
					continue
				for i in [0, 2, 3, 4, 1]:
					menu = by_name("Episode actions", browser)
					await click(menu)
					await pick_item(menu.get_popup(), i)
					await settle(browser)
				if Store.current_page == "queue":
					await click_name("Providers")
					await settle(browser)
					await click(by_name(label, browser))
					await settle(browser)
				for title in ["Add newest from all shows", "Play newest next"]:
					await click(by_name(title, browser))
					await settle(browser)
				check(Util.number((await Backend.snapshot()).get("total")) > 0, "local RSS episodes queued")
	await shot("podcast_collection")

func settle(browser: ProviderBrowser) -> void:
	await wait(0.25)
	for i in 200:
		if not browser._busy and not browser._loading:
			break
		await wait(0.1)
