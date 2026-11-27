# Форк Task Manager / Icons-Only Task Manager.
# Ставится только в ~/.local/share/plasma/plasmoids — /usr не трогаем.

TM_ID   := local.vyuyukin.taskbar
ICON_ID := local.vyuyukin.iconbar

PLASMOIDS_DIR := $(HOME)/.local/share/plasma/plasmoids

# Старые Id форка (до переименования) — вычищаются при uninstall.
LEGACY_TM_ID   := local.vyuyukin.taskmanager
LEGACY_ICON_ID := local.vyuyukin.icontasks

.PHONY: *

## Установить оба пакета (основной + алиас «только иконки»)
install:
	kpackagetool6 --type=Plasma/Applet --install=./package || kpackagetool6 --type=Plasma/Applet --upgrade=./package
	kpackagetool6 --type=Plasma/Applet --install=./package-icontasks || kpackagetool6 --type=Plasma/Applet --upgrade=./package-icontasks
	@echo "Готово. Если виджет не виден в «Добавить элементы», перезапусти панель:"
	@echo "  systemctl --user restart plasma-plasmashell"

## Переустановить после правок QML (kpackage кэширует, upgrade обязателен)
upgrade: install

## Удалить форк из системы (панель при этом не ломается — это отдельные Id).
## Пакет-обёртка с X-Plasma-RootPath не имеет своего mainscript, поэтому
## kpackagetool6 отказывается его удалять — для таких Id нужен rm -rf.
uninstall:
	@for id in $(TM_ID) $(ICON_ID) $(LEGACY_TM_ID) $(LEGACY_ICON_ID); do \
		dir="$(PLASMOIDS_DIR)/$$id"; \
		if kpackagetool6 --type=Plasma/Applet --remove=$$id >/dev/null 2>&1; then \
			echo "удалён (kpackagetool6): $$id"; \
		elif [ -d "$$dir" ]; then \
			rm -rf "$$dir" && echo "удалён (rm -rf): $$id"; \
		else \
			echo "нет такого: $$id"; \
		fi; \
	done

## Проверить, что установилось
status:
	@kpackagetool6 --type=Plasma/Applet --list | grep -E '$(TM_ID)|$(ICON_ID)' || echo "не установлено"
	@echo "--- старые Id в $(PLASMOIDS_DIR) (должно быть пусто):"
	@ls -1d $(PLASMOIDS_DIR)/$(LEGACY_TM_ID) $(PLASMOIDS_DIR)/$(LEGACY_ICON_ID) 2>/dev/null || true

## Собрать .plasmoid-архивы (для установки через «Установить из файла…»)
package:
	cd ./package && zip -r - ./* > ../taskmanager-fork.plasmoid
	cd ./package-icontasks && zip -r - ./* > ../icontasks-fork.plasmoid

## diff с системной версией — что именно ты изменил
diff:
	diff -ruN /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager ./package | head -200
