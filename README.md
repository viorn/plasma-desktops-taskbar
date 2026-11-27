# plasma-taskmanager (fork)

Форк стандартных виджетов Plasma 6 **Task Manager** и **Icons-Only Task Manager**,
скопированный из `/usr/share/plasma/plasmoids/org.kde.plasma.taskmanager`
(пакет `plasma-desktop-data 4:6.3.6-2`).

Ничего в `/usr` не перезаписывается: форк ставится в `~/.local/share/plasma/plasmoids`
под своим Id, поэтому штатный виджет и текущая панель остаются нетронутыми.

## Что внутри

```
package/                 # основной виджет — копия org.kde.plasma.taskmanager
├── metadata.json        # Id: local.vyuyukin.taskbar
└── contents/
    ├── config/          # main.xml (KConfigXT: все настройки и дефолты), config.qml
    └── ui/              # main.qml, Task.qml, TaskList.qml, ContextMenu.qml, ...
package-icontasks/       # алиас «только иконки»
└── metadata.json        # Id: local.vyuyukin.iconbar + X-Plasma-RootPath на форк
```

Как устроен «Icons-Only» в апстриме: это **не отдельный код**, а пакет-обёртка
с `"X-Plasma-RootPath": "org.kde.plasma.taskmanager"` (один `metadata.json`, ни строчки QML).
Поведение переключается в `package/contents/ui/main.qml`:

```qml
readonly property bool iconsOnly: Plasmoid.pluginName === "org.kde.plasma.icontasks"
```

В апстриме эта проверка продублирована ещё в шести файлах (`layoutmetrics.js`,
`TaskBadgeOverlay.qml`, `ConfigBehavior.qml` ×6, `ConfigAppearance.qml`), поэтому в форке
она сведена в **одно место** — `contents/ui/code/identity.js`:

```js
const PACKAGE_ID             = "local.vyuyukin.taskbar";
const ICONS_ONLY_PACKAGE_ID  = "local.vyuyukin.iconbar";

function isIconsOnly(pluginName) {
    return pluginName === ICONS_ONLY_PACKAGE_ID
        || pluginName === "org.kde.plasma.icontasks"; // совместимость с апстримом
}
```

а вызовы выглядят так:

```qml
import "code/identity.js" as ForkIdentity
readonly property bool iconsOnly: ForkIdentity.isIconsOnly(Plasmoid.pluginName)
```

Меняешь Id виджета — правишь `identity.js`, оба `metadata.json` и `TM_ID`/`ICON_ID` в `Makefile`.

## Группировка по рабочим столам (фича форка)

Ключ конфига `groupByDesktop` (по умолчанию **включён**). Что делает:

- рисует **пейджер-чипы** с именами рабочих столов («00», «01», …), подсвечивает текущий,
  клик переключает стол (`PagerModel.changePage`);
- раскладывает задачи **группами по столам**, между группами — разделитель; столы без окон
  не занимают места;
- заголовки групп не нужны: имя стола даёт чип, а группа идёт следом в том же порядке.

Код: `DesktopPager.qml` (чипы), группы — в `main.qml` (Repeater по `virtualDesktopInfo.desktopIds`,
свой `TaskManager.TasksModel` на стол), `TaskList.qml` стал переиспользуемым (`taskModel` + `tasksRoot`).

Важно: у каждой задачи и каждого пункта меню действие идёт **в модель своей группы** —
для этого `taskModel` проброшен в `Task.qml`, `ContextMenu.qml`, `GroupDialog.qml`,
`ToolTipDelegate/Instance/WindowMouseArea`, `MouseHandler.qml` и `code/tools.js`.

Ограничения текущей версии (осознанные, см. `.agents/protocols/group-by-desktop`):

| Ограничение | Причина |
|---|---|
| Закреплённые приложения видны только в группе **текущего** стола | лончеры не хранят стол (`VirtualDesktops=[0]`); per-desktop pin — следующий этап |
| Колесо мыши по задачам в этом режиме не работает | нужен обход по всем группам |
| Если суммарная ширина групп больше панели — лишнее обрезается | нет прокрутки/сворачивания групп |
| Автопереноса окон на «свой» стол нет | нужен отдельный слой (D-Bus/KWin-правила), этап M4 |

## Установка / итерации

```bash
make install     # поставить оба пакета
make upgrade     # = install, после каждой правки QML
make status      # проверить, что пакеты видны
make diff        # diff с системным виджетом — что именно изменено
make uninstall   # убрать форк
```

После `make install`, если виджета нет в списке: `systemctl --user restart plasma-plasmashell`
(KWin при этом не трогается, панель просто перерисуется).

Добавить на панель: ПКМ → «Добавить элементы…» → «Окна и задачи» →
*Taskbar (fork)* или *Icon Taskbar (fork)*.

Быстрый просмотр без панели: `plasmoidviewer -a local.vyuyukin.taskbar`
(нужен пакет `plasma-sdk`).

## Куда смотреть, когда допиливаешь

| Задача | Файл |
|---|---|
| Раскладка/поведение списка задач | `contents/ui/main.qml`, `TaskList.qml` |
| Внешний вид одной иконки, бейджи, прогресс | `Task.qml`, `Badge.qml`, `TaskProgressOverlay.qml` |
| Клики, скролл, средняя кнопка | `MouseHandler.qml` |
| Контекстное меню | `ContextMenu.qml` |
| Тултипы и превью окон | `ToolTipInstance.qml`, `ToolTipDelegate.qml`, `PipeWireThumbnail.qml` |
| Новые настройки | `contents/config/main.xml` (ключи + дефолты) и `ConfigAppearance.qml` / `ConfigBehavior.qml` |
| Вспомогательная логика | `contents/ui/code/tools.js`, `code/layoutmetrics.js` |
| Id пакета / «только иконки» | `contents/ui/code/identity.js` |

Полезно помнить: `main.qml` строит `TasksModel` (из `org.kde.taskmanager`) и дальше всё
крутится вокруг ролей модели — та же `TaskManager.TasksModel`, из которой Tasks Minimap
читает `Geometry` (роль 289). Поэтому «сортировка/группировка по позиции окна» в форке
делается там же, где сейчас `sortingStrategy`.

## Апстрим

- `invent.kde.org/plasma/plasma-desktop` → `applets/taskmanager`
- Точная версия под систему: `git checkout v6.3.6`
- В каталоге есть `contents/config/main.xml.dpkg-distrib` — след локальной правки
  системного файла; `make diff` его тоже покажет.
