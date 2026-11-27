# plasma-taskmanager (fork)

Форк стандартных виджетов Plasma 6 **Task Manager** и **Icons-Only Task Manager**
(в системе называются *Desktops + Taskbar* / *Desktops + Icon Taskbar*),
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

Ключ конфига `groupByDesktop` (по умолчанию **включён**). Раскладка — «стол + его окна»:

```
[00|▓ ▓ ▓][01|▓ ▓][10|▓ ▓ ▓ ▓][11|]
 └ подпись   └ иконки только этого рабочего стола
```

- каждая группа — **подпись стола** (`DesktopHeader.qml`) и следом иконки окон этого стола;
- подпись = имя рабочего стола из KWin, а если имя пустое — его номер (1, 2, …);
- текущий стол подсвечен, клик по подписи переключает на него (`PagerModel.changePage`);
- столы **без окон тоже видны** (остаётся одна подпись) — так виджет работает и как индикатор;
- между группами тонкий разделитель.

Код: `DesktopHeader.qml` (подпись), группы — в `main.qml` (Repeater по `virtualDesktopInfo.desktopIds`,
свой `TaskManager.TasksModel` на стол), `TaskList.qml` стал переиспользуемым (`taskModel` + `tasksRoot`).

Грабли: `VirtualDesktopInfo.desktopNames` наполняется асинхронно и **не сигналит** об этом
(в пробе все `desktopNamesChanged` пришли с пустыми именами), поэтому имена подтягиваются
таймером в `tasks.desktopNames` (см. комментарий в `main.qml`).

Важно: у каждой задачи и каждого пункта меню действие идёт **в модель своей группы** —
для этого `taskModel` проброшен в `Task.qml`, `ContextMenu.qml`, `GroupDialog.qml`,
`ToolTipDelegate/Instance/WindowMouseArea`, `MouseHandler.qml` и `code/tools.js`.

### Закрепление приложения за рабочим столом

Лончеры в KDE про столы ничего не знают (`VirtualDesktops=[0]`, `IsOnAllVirtualDesktops=true`),
поэтому форк хранит закрепления сам — в конфиге `launcherDesktops`, список строк
`<desktopId>=<launcherUrl>`. **По умолчанию список пуст**: закрепления штатного виджета
(`launcherList`) в режиме групп не показываются вообще.

- ПКМ по окну → «Закрепить за столом "01"» / «Открепить от стола "01"»
  (пункты подменяются только при включённом `groupByDesktop`);
- перетаскивание `.desktop` на виджет и запросы извне (`addLauncher`) тоже закрепляют
  за **текущим** столом;
- клик по закреплённому приложению чужого стола: виджет переключается на этот стол
  и только потом запускает приложение (ждёт смены `currentDesktop`, максимум ~2 с).

Код: `launchersFor()`, `addLauncherToDesktop()`, `removeLauncherFromDesktop()`,
`launchOnDesktop()` в `main.qml`; пункты меню — в `ContextMenu.qml`.

### Перетаскивание мышью

- **Порядок закреплённых** внутри стола: тащите иконку закреплённого приложения на другую —
  порядок записей `launcherDesktops` перепишется по отпусканию (визуально иконки
  переставляются уже после drop, живого «разъезжания» под курсором нет — порядок живёт в конфиге).
- **Окно на другой рабочий стол**: тащите иконку окна в другую группу (подпись стола
  подсвечивается) — у окна вызывается `requestVirtualDesktops(index, [desktopId])`.
- **Закрепление переезжает вместе с окном**: если приложение было закреплено за исходным
  столом, запись в `launcherDesktops` переносится на целевой стол.
- **Закрепление без окна** (лончер): тащите на другой стол — запись `launcherDesktops`
  просто меняет `desktopId`, приложение нигде не запускается.
- Внутри одного стола перетаскивание окон работает как в апстриме (только при
  «Сортировать вручную»), между группами — всегда.

### Быстрые клавиши Meta+1…0

Клавиши регистрирует **plasmashell** (`ShellCorona`, «Activate Task Manager Entry N»), а сам
виджет получает вызов `activateTaskAtIndex(QVariant)` — апплет ищется по
`X-Plasma-Provides: org.kde.plasma.multitasking`. То есть клавиши — часть виджета.

В режиме групп нумерация идёт **в рамках текущего рабочего стола**: Meta+1 — первая иконка
в группе активного стола, Meta+2 — вторая и т.д. (раньше нумерация шла по всем группам сразу,
да ещё и считала служебный `Repeater` внутри `children`). При выключенной группировке поведение
как в апстриме — все задачи по порядку.

Ограничения текущей версии (осознанные, см. `.agents/protocols/group-by-desktop`):

| Ограничение | Причина |
|---|---|
| Колесо мыши по задачам в этом режиме не работает | нужен обход по всем группам |
| Если суммарная ширина групп больше панели — лишнее обрезается | нет прокрутки/сворачивания групп |
| Автопереноса окон на «свой» стол нет | нужен отдельный слой (D-Bus/KWin-правила), этап M4 |
| Если удалить рабочий стол, его закрепления остаются в конфиге | записи по UUID, чистки нет |
| Пока приложение запускается, его иконка есть в моделях всех столов | стартовая задача не знает стола (`VirtualDesktops=[0]`); показывается только в группе текущего стола, но `model.count` группы на секунду больше |

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
*Desktops + Taskbar* или *Desktops + Icon Taskbar*.

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
