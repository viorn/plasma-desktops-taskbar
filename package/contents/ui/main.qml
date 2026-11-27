/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

import org.kde.plasma.workspace.trianglemousefilter

import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.taskmanager as TaskManagerApplet
import org.kde.plasma.private.pager as Pager
import org.kde.plasma.workspace.dbus as DBus

import "code/identity.js" as ForkIdentity
import "code/layoutmetrics.js" as LayoutMetrics
import "code/tools.js" as TaskTools

PlasmoidItem {
    id: tasks

    // For making a bottom to top layout since qml flow can't do that.
    // We just hang the task manager upside down to achieve that.
    // This mirrors the tasks and group dialog as well, so we un-rotate them
    // to fix that (see Task.qml and GroupDialog.qml).
    rotation: Plasmoid.configuration.reverseMode && Plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

    readonly property bool shouldShrinkToZero: tasksModel.count === 0
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // fork: «кто мы такие» определяется в одном месте — code/identity.js
    readonly property bool iconsOnly: ForkIdentity.isIconsOnly(Plasmoid.pluginName)
    // fork: задачи раскладываются группами по виртуальным рабочим столам,
    // а подпись группы работает ещё и как пейджер (см. README).
    readonly property bool groupByDesktop: Plasmoid.configuration.groupByDesktop

    // fork: имена рабочих столов VirtualDesktopInfo отдаёт асинхронно: список
    // наполняется уже после создания апплета, причём без desktopNamesChanged
    // (в пробе все 4 сигнала пришли с пустыми именами). Поэтому держим свою
    // копию и подтягиваем её таймером — иначе подписи групп остаются пустыми.
    property var desktopNames: []

    // Подпись группы: имя рабочего стола, а если оно пустое — номер (с 1).
    // names передаётся аргументом, иначе QML не увидит зависимость от
    // tasks.desktopNames и подпись не обновится, когда имена доедут.
    function desktopLabel(index: int, names: var): string {
        const name = names ? names[index] : undefined;
        if (name !== undefined && name !== null && String(name).length > 0) {
            return String(name);
        }
        return String(index + 1);
    }

    function desktopNamesEqual(a, b): bool {
        if (!a || !b || a.length !== b.length) {
            return false;
        }
        for (let i = 0; i < a.length; ++i) {
            if (String(a[i]) !== String(b[i])) {
                return false;
            }
        }
        return true;
    }

    // fork: закрепление приложения за конкретным рабочим столом.
    // Хранится в конфиге как список строк "desktopId=launcherUrl".
    // По умолчанию список пуст: закрепления штатного виджета не наследуются.
    readonly property var launcherDesktops: Plasmoid.configuration.launcherDesktops

    // entries передаётся аргументом — иначе QML не увидит зависимость от конфига.
    function launchersFor(desktopId: string, entries: var): var {
        const result = [];
        if (!entries) {
            return result;
        }
        const prefix = String(desktopId) + "=";
        for (let i = 0; i < entries.length; ++i) {
            const entry = String(entries[i]);
            if (entry.startsWith(prefix)) {
                result.push(entry.substring(prefix.length));
            }
        }
        return result;
    }

    // ?icon=… в URL — только подсказка для иконки, для сравнения её отбрасываем.
    function launcherKey(url): string {
        const value = String(url);
        const iconQuery = value.indexOf("?icon=");
        return iconQuery === -1 ? value : value.substring(0, iconQuery);
    }

    function hasLauncherOnDesktop(url: url, desktopId: string, entries: var): bool {
        const key = tasks.launcherKey(url);
        return tasks.launchersFor(desktopId, entries).some(entry => entry === key);
    }

    function addLauncherToDesktop(url: url, desktopId: string): void {
        if (Plasmoid.immutability === PlasmaCore.Types.SystemImmutable || !desktopId) {
            return;
        }
        const entries = tasks.launcherDesktops ? Array.from(tasks.launcherDesktops).map(String) : [];
        const entry = String(desktopId) + "=" + tasks.launcherKey(url);
        if (entries.indexOf(entry) !== -1) {
            return;
        }
        entries.push(entry);
        Plasmoid.configuration.launcherDesktops = entries;
    }

    // Перезаписывает закрепления одного стола, сохраняя порядок остальных.
    function setLaunchersFor(desktopId: string, urls: var): void {
        const all = tasks.launcherDesktops ? Array.from(tasks.launcherDesktops).map(String) : [];
        const prefix = String(desktopId) + "=";
        const result = [];
        let inserted = false;
        for (let i = 0; i < all.length; ++i) {
            if (String(all[i]).startsWith(prefix)) {
                if (!inserted) {
                    for (let j = 0; j < urls.length; ++j) {
                        result.push(prefix + tasks.launcherKey(urls[j]));
                    }
                    inserted = true;
                }
            } else {
                result.push(String(all[i]));
            }
        }
        if (!inserted) {
            for (let j = 0; j < urls.length; ++j) {
                result.push(prefix + tasks.launcherKey(urls[j]));
            }
        }
        Plasmoid.configuration.launcherDesktops = result;
    }

    // Перестановка закрепления внутри стола (drag-n-drop по иконкам).
    function reorderLauncherPin(desktopId: string, fromUrl, toUrl, after: bool): void {
        const urls = tasks.launchersFor(desktopId, tasks.launcherDesktops);
        const fromKey = tasks.launcherKey(fromUrl);
        const toKey = tasks.launcherKey(toUrl);
        if (urls.indexOf(fromKey) === -1 || urls.indexOf(toKey) === -1 || fromKey === toKey) {
            return;
        }
        urls.splice(urls.indexOf(fromKey), 1);
        const to = urls.indexOf(toKey);
        urls.splice(after ? to + 1 : to, 0, fromKey);
        tasks.setLaunchersFor(desktopId, urls);
    }

    // Перенос закрепления на другой рабочий стол.
    function moveLauncherPin(url, fromDesktopId: string, toDesktopId: string): void {
        if (!fromDesktopId || !toDesktopId || fromDesktopId === toDesktopId) {
            return;
        }
        const key = tasks.launcherKey(url);
        const all = tasks.launcherDesktops ? Array.from(tasks.launcherDesktops).map(String) : [];
        const fromEntry = String(fromDesktopId) + "=" + key;
        const toEntry = String(toDesktopId) + "=" + key;
        const result = all.filter(entry => entry !== fromEntry && entry !== toEntry);
        result.push(toEntry);
        Plasmoid.configuration.launcherDesktops = result;
    }

    function removeLauncherFromDesktop(url: url, desktopId: string): void {
        if (Plasmoid.immutability === PlasmaCore.Types.SystemImmutable || !desktopId) {
            return;
        }
        const entries = tasks.launcherDesktops ? Array.from(tasks.launcherDesktops).map(String) : [];
        const entry = String(desktopId) + "=" + tasks.launcherKey(url);
        const index = entries.indexOf(entry);
        if (index === -1) {
            return;
        }
        entries.splice(index, 1);
        Plasmoid.configuration.launcherDesktops = entries;
    }

    // fork: что под курсором при перетаскивании внутри виджета — нужно, чтобы
    // переносить задачи и закрепления между группами (рабочими столами).
    property var dragOverItem: null
    property var dragOverGroup: null
    // Перенос уже применён для текущего драга — защита от двойного применения
    // (drop и конец драга приходят в неопределённом порядке).
    property bool dragApplied: false
    // Диагностика drag-n-drop: при true все шаги перетаскивания пишутся в
    // journal (journalctl --user -u plasma-plasmashell, строки «[dnd]»).
    // По умолчанию выключена — включать только на время отладки.
    readonly property bool dndDebug: false

    function dndLog(message: string): void {
        if (tasks.dndDebug) {
            console.warn("[dnd] " + message);
        }
    }

    // fork: запуск приложения из группы другого стола — сначала переключаемся
    // на этот стол, потом запускаем (иначе окно откроется на текущем).
    // index — QModelIndex строки лончера в модели группы.
    property var pendingLaunch: null
    property string pendingLaunchDesktop: ""
    property int pendingLaunchTries: 0

    function launchOnDesktop(index, taskModel, modifiers = 0): void {
        const desktop = taskModel ? taskModel.virtualDesktop : undefined;
        const position = desktop === undefined ? -1 : virtualDesktopInfo.desktopIds.indexOf(desktop);
        const activate = () => {
            if (modifiers & Qt.ShiftModifier) {
                taskModel.requestNewInstance(index);
            } else {
                taskModel.requestActivate(index);
            }
        };
        if (position === -1 || desktop === virtualDesktopInfo.currentDesktop) {
            activate();
            return;
        }
        tasks.pendingLaunch = activate;
        tasks.pendingLaunchDesktop = String(desktop);
        tasks.pendingLaunchTries = 0;
        tasks.switchToDesktop(position);
        // Ждём, пока KWin действительно переключит стол (см. launchTimer).
        launchTimer.restart();
    }

    property Task toolTipOpenedByClick
    property Task toolTipAreaItem

    readonly property Component contextMenuComponent: Qt.createComponent("ContextMenu.qml")
    readonly property Component pulseAudioComponent: Qt.createComponent("PulseAudio.qml")

    property bool needLayoutRefresh: false
    property /*list<WId> where WId = int|string*/ var taskClosedWithMouseMiddleButton: []
    property alias taskList: taskList

    preferredRepresentation: fullRepresentation

    Plasmoid.constraintHints: Plasmoid.CanFillArea

    Plasmoid.onUserConfiguringChanged: {
        if (Plasmoid.userConfiguring && groupDialog !== null) {
            groupDialog.visible = false;
        }
    }

    // Форк: в режиме групп ширину задаёт содержимое (groupsRow), иначе панель
    // держала апплет на минимуме: Layout.preferredWidth считался как
    // Math.min(width, groupsRow.width), то есть от собственной ширины, и
    // «залипал» на Layout.minimumWidth (в живой панели апплет был 30x30 при
    // контенте 640+ px — все группы рисовались мимо него, а перетаскивание
    // работало только в первых 30 px, т.е. в начале первой группы).
    Layout.fillWidth: vertical ? true : (groupByDesktop ? false : Plasmoid.configuration.fill)
    Layout.fillHeight: !vertical ? true : (groupByDesktop ? false : Plasmoid.configuration.fill)
    Layout.minimumWidth: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        return vertical ? 0 : LayoutMetrics.preferredMinWidth();
    }
    Layout.minimumHeight: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        return !vertical ? 0 : LayoutMetrics.preferredMinHeight();
    }

//BEGIN TODO: this is not precise enough: launchers are smaller than full tasks
    Layout.preferredWidth: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            return Kirigami.Units.gridUnit * 10;
        }
        if (groupByDesktop) {
            return groupsRow.width;
        }
        return taskList.Layout.maximumWidth
    }
    Layout.preferredHeight: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            if (groupByDesktop) {
                return groupsRow.height;
            }
            return taskList.Layout.maximumHeight
        }
        return Kirigami.Units.gridUnit * 2;
    }
//END TODO

    property Item dragSource

    signal requestLayout
    signal windowsHovered(var winIds, bool hovered)
    signal activateWindowView(var winIds)

    onDragSourceChanged: {
        if (dragSource === null) {
            tasksModel.syncLaunchers();
        }
    }

    function publishIconGeometries(taskItems: /*list<Item>*/var): void {
        if (TaskTools.taskManagerInstanceCount >= 2) {
            return;
        }
        for (let i = 0; i < taskItems.length - 1; ++i) {
            const task = taskItems[i];

            if (!task.model.IsLauncher && !task.model.IsStartup) {
                const model = task.taskModel || tasksModel;
                model.requestPublishDelegateGeometry(model.makeModelIndex(task.index),
                    backend.globalRect(task), task);
            }
        }
    }

    // Все Task-элементы в порядке отображения: либо один список (апстрим),
    // либо группы по рабочим столам в порядке desktopIds.
    // В children списка кроме делегатов Task есть ещё сам Repeater (он тоже Item
    // и тоже имеет свойство model), поэтому берём только делегаты — у них задан
    // taskList (так же поступает апстрим, обращаясь к Repeater.itemAt()).
    function taskItemsOf(list): var {
        const items = [];
        if (!list) {
            return items;
        }
        const children = list.children;
        for (let i = 0; i < children.length; ++i) {
            const child = children[i];
            if (child && child.taskList !== undefined && child.model !== undefined && child.model !== null) {
                items.push(child);
            }
        }
        return items;
    }

    function visibleTaskItems(): var {
        if (!groupByDesktop) {
            return tasks.taskItemsOf(taskList);
        }

        let items = [];
        for (let i = 0; i < desktopGroupRepeater.count; ++i) {
            const group = desktopGroupRepeater.itemAt(i);
            if (group && group.visible && group.list) {
                items = items.concat(tasks.taskItemsOf(group.list));
            }
        }
        return items;
    }

    // Задачи группы текущего рабочего стола — для Meta+1..9: нумерация идёт
    // в рамках своего стола, а не по всем группам.
    function currentDesktopTaskItems(): var {
        if (!groupByDesktop) {
            return tasks.taskItemsOf(taskList);
        }

        const current = virtualDesktopInfo.currentDesktop;
        for (let i = 0; i < desktopGroupRepeater.count; ++i) {
            const group = desktopGroupRepeater.itemAt(i);
            if (group && group.modelData === current) {
                return tasks.taskItemsOf(group.list);
            }
        }
        return [];
    }

    // Поиск задачи под точкой (координаты в системe container) — для MouseHandler,
    // который иначе умеет искать только в одном списке.
    function taskItemAt(container, x, y): var {
        for (let i = 0; i < desktopGroupRepeater.count; ++i) {
            const group = desktopGroupRepeater.itemAt(i);
            if (!group || !group.visible || !group.list) {
                continue;
            }

            const list = group.list;
            const point = list.mapFromItem(container, x, y);
            if (point.x >= 0 && point.y >= 0 && point.x <= list.width && point.y <= list.height) {
                const item = list.childAt(point.x, point.y);
                if (item) {
                    return item;
                }
            }
        }
        return null;
    }

    // Группа (рабочий стол) под точкой в координатах container.
    function groupAt(container, x, y): var {
        for (let i = 0; i < desktopGroupRepeater.count; ++i) {
            const group = desktopGroupRepeater.itemAt(i);
            if (!group || !group.visible) {
                continue;
            }

            const point = group.mapFromItem(container, x, y);
            if (point.x >= 0 && point.y >= 0 && point.x <= group.width && point.y <= group.height) {
                return group;
            }
        }
        return null;
    }

    // Закреплено ли приложение этой строки на своём столе. У закреплённого
    // приложения строка модели может быть окном (IsLauncher=false), но порядок
    // всё равно задаёт конфиг launcherDesktops.
    function isPinnedOnSourceDesktop(item): bool {
        if (!item || !item.model || !item.taskModel) {
            return false;
        }
        const desktopId = item.taskModel.virtualDesktop !== undefined
            ? String(item.taskModel.virtualDesktop) : "";
        if (!desktopId) {
            return false;
        }
        return tasks.hasLauncherOnDesktop(item.model.LauncherUrlWithoutIcon, desktopId,
            tasks.launcherDesktops);
    }

    // Живая перестановка закреплений под курсором (как в апстриме, где порядок
    // меняет model.move()). Порядок живёт в конфиге, но libtaskmanager на
    // изменение launcherList двигает строки через moveRows, поэтому делегат,
    // который тащат, не пересоздаётся (проверено probe51: same=true).
    // Гистерезис по последней цели: после перестановки под курсором оказывается
    // соседняя иконка, и без этого порядка «дрожал» бы.
    property var dragPinnedAim: null

    function reorderPinLive(source, above): void {
        if (!source || !source.model || !above || !above.model || above === source) {
            return;
        }
        if (above === tasks.dragPinnedAim) {
            return;
        }
        if (!tasks.isPinnedOnSourceDesktop(source) || !tasks.isPinnedOnSourceDesktop(above)) {
            return;
        }
        if (!source.taskModel || !above.taskModel
                || String(source.taskModel.virtualDesktop) !== String(above.taskModel.virtualDesktop)) {
            return;
        }
        tasks.dragPinnedAim = above;
        tasks.reorderLauncherPin(String(source.taskModel.virtualDesktop),
            source.model.LauncherUrlWithoutIcon, above.model.LauncherUrlWithoutIcon,
            above.index > source.index);
    }

    // Завершение перетаскивания внутри виджета: перенос задачи или закрепления
    // в другую группу (рабочий стол) либо перестановка закреплений.
    // Порядок закреплений живёт в конфиге (launcherDesktops), поэтому переставляем
    // не строки модели, а записи конфига.
    // Вызывается дважды — из MouseHandler.onDropped и по концу драга: порядок
    // этих событий не гарантирован, а в панели drop может вообще не дойти.
    // Повторный вызов отсекает tasks.dragApplied.
    function finishDrag(source, overItem, overGroup): void {
        tasks.dragOverGroup = null;
        tasks.dragOverItem = null;
        tasks.dragPinnedAim = null;

        if (!source || !source.model) {
            tasks.dndLog("finish: no source");
            return;
        }

        if (tasks.dragApplied) {
            tasks.dndLog("finish: already applied, skip");
            return;
        }
        tasks.dragApplied = true;

        const sourceDesktop = source.taskModel && source.taskModel.virtualDesktop !== undefined
            ? String(source.taskModel.virtualDesktop) : "";
        const targetDesktop = overGroup ? String(overGroup.modelData) : "";
        const url = source.model.LauncherUrlWithoutIcon;
        // Закрепление есть не только у строк-лончеров: у запущенного
        // закреплённого приложения строка — окно, но порядок его иконки всё
        // равно задаётся конфигом.
        const pinned = tasks.isPinnedOnSourceDesktop(source);

        tasks.dndLog("finish: app=" + source.model.AppName
            + " launcher=" + (source.model.IsLauncher === true)
            + " pinned=" + pinned
            + " src=" + sourceDesktop.substring(0, 8)
            + " dst=" + (targetDesktop ? targetDesktop.substring(0, 8) : "none")
            + " overItem=" + (overItem && overItem.model ? overItem.model.AppName : "null"));

        if (targetDesktop && targetDesktop !== sourceDesktop) {
            // Переезд на другой стол: закрепление едет вместе с приложением,
            // окно — только если это не строка-лончер.
            if (pinned) {
                tasks.moveLauncherPin(url, sourceDesktop, targetDesktop);
            }
            if (source.model.IsLauncher !== true) {
                source.taskModel.requestVirtualDesktops(source.modelIndex(), [targetDesktop]);
            }
            return;
        }

        // Тот же стол: порядок закреплений живёт в конфиге, поэтому переставляем
        // запись конфига, а не строку модели (иначе модель и конфиг разъедутся
        // и иконка вернётся на место).
        if (!pinned || !overItem || overItem === source || !overItem.model) {
            return;
        }

        if (!tasks.isPinnedOnSourceDesktop(overItem)) {
            return;
        }

        tasks.reorderLauncherPin(sourceDesktop, url,
            overItem.model.LauncherUrlWithoutIcon, overItem.index > source.index);
    }

    readonly property TaskManager.TasksModel tasksModel: TaskManager.TasksModel {
        id: tasksModel

        readonly property int logicalLauncherCount: {
            if (Plasmoid.configuration.separateLaunchers) {
                return launcherCount;
            }

            let startupsWithLaunchers = 0;

            const items = tasks.visibleTaskItems();
            for (let i = 0; i < items.length; ++i) {
                const item = items[i];

                // During destruction required properties such as item.model can go null for a while,
                // so in paths that can trigger on those moments, they need to be guarded
                if (item?.model?.IsStartup && item.model.HasLauncher) {
                    ++startupsWithLaunchers;
                }
            }

            return launcherCount + startupsWithLaunchers;
        }

        virtualDesktop: virtualDesktopInfo.currentDesktop
        screenGeometry: Plasmoid.containment.screenGeometry
        activity: activityInfo.currentActivity

        filterByVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen
        filterByActivity: Plasmoid.configuration.showOnlyCurrentActivity
        filterNotMinimized: Plasmoid.configuration.showOnlyMinimized

        hideActivatedLaunchers: tasks.iconsOnly || Plasmoid.configuration.hideLauncherOnStart
        sortMode: sortModeEnumValue(Plasmoid.configuration.sortingStrategy)
        launchInPlace: tasks.iconsOnly && Plasmoid.configuration.sortingStrategy === 1
        separateLaunchers: {
            if (!tasks.iconsOnly && !Plasmoid.configuration.separateLaunchers
                && Plasmoid.configuration.sortingStrategy === 1) {
                return false;
            }

            return true;
        }

        groupMode: groupModeEnumValue(Plasmoid.configuration.groupingStrategy)
        groupInline: !Plasmoid.configuration.groupPopups && !tasks.iconsOnly
        groupingWindowTasksThreshold: (Plasmoid.configuration.onlyGroupWhenFull && !tasks.iconsOnly
            ? LayoutMetrics.optimumCapacity(width, height) + 1 : -1)

        onLauncherListChanged: {
            Plasmoid.configuration.launchers = launcherList;
        }

        onGroupingAppIdBlacklistChanged: {
            Plasmoid.configuration.groupingAppIdBlacklist = groupingAppIdBlacklist;
        }

        onGroupingLauncherUrlBlacklistChanged: {
            Plasmoid.configuration.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist;
        }

        function sortModeEnumValue(index: int): /*TaskManager.TasksModel.SortMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.SortDisabled;
            case 1:
                return TaskManager.TasksModel.SortManual;
            case 2:
                return TaskManager.TasksModel.SortAlpha;
            case 3:
                return TaskManager.TasksModel.SortVirtualDesktop;
            case 4:
                return TaskManager.TasksModel.SortActivity;
            default:
                return TaskManager.TasksModel.SortDisabled;
            }
        }

        function groupModeEnumValue(index: int): /*TaskManager.TasksModel.GroupMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.GroupDisabled;
            case 1:
                return TaskManager.TasksModel.GroupApplications;
            }
        }

        Component.onCompleted: {
            launcherList = Plasmoid.configuration.launchers;
            groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;

            // Only hook up view only after the above churn is done.
            taskRepeater.model = tasksModel;
        }
    }

    readonly property TaskManagerApplet.Backend backend: TaskManagerApplet.Backend {
        id: backend
        highlightWindows: Plasmoid.configuration.highlightWindows

        onAddLauncher: {
            tasks.addLauncher(url);
        }
    }

    DBus.DBusServiceWatcher {
        id: effectWatcher
        busType: DBus.BusType.Session
        watchedService: "org.kde.KWin.Effect.WindowView1"
    }

    readonly property Component taskInitComponent: Component {
        Timer {
            interval: 200
            running: true

            onTriggered: {
                const task = parent as Task;
                // В форке у задачи своя модель (группа рабочего стола), поэтому индекс
                // строим по ней. Вызов task.modelIndex() здесь ломается, когда контекст
                // делегата уже невалиден (задача успела пересоздаться).
                const model = task ? (task.taskModel || tasksModel) : null;
                if (task && model) {
                    model.requestPublishDelegateGeometry(model.makeModelIndex(task.index), backend.globalRect(task), task);
                }
                destroy();
            }
        }
    }

    Connections {
        target: Plasmoid

        function onLocationChanged(): void {
            if (TaskTools.taskManagerInstanceCount >= 2) {
                return;
            }
            // This is on a timer because the panel may not have
            // settled into position yet when the location prop-
            // erty updates.
            iconGeometryTimer.start();
        }
    }

    Connections {
        target: Plasmoid.containment

        function onScreenGeometryChanged(): void {
            iconGeometryTimer.start();
        }
    }

    Mpris.Mpris2Model {
        id: mpris2Source
    }

    Item {
        anchors.fill: parent

        TaskManager.VirtualDesktopInfo {
            id: virtualDesktopInfo
        }

        // Переключение рабочих столов из подписей групп (тот же механизм,
        // что использует штатный апплет «Пейджер»).
        Pager.PagerModel {
            id: desktopPagerModel
            enabled: tasks.groupByDesktop
            pagerType: Pager.PagerModel.VirtualDesktops
            screenGeometry: Plasmoid.containment.screenGeometry
        }

        TaskManager.ActivityInfo {
            id: activityInfo
            readonly property string nullUuid: "00000000-0000-0000-0000-000000000000"
        }

        Loader {
            id: pulseAudio
            sourceComponent: pulseAudioComponent
            active: pulseAudioComponent.status === Component.Ready
        }

        // fork: отложенный запуск приложения после переключения рабочего стола
        // (см. tasks.launchOnDesktop).
        Timer {
            id: launchTimer

            interval: 100
            repeat: true

            onTriggered: {
                // Ждём, пока KWin применит переключение (но не дольше ~2 с),
                // иначе окно успеет открыться на старом рабочем столе.
                if (tasks.pendingLaunchDesktop !== ""
                    && String(virtualDesktopInfo.currentDesktop) !== tasks.pendingLaunchDesktop
                    && ++tasks.pendingLaunchTries < 20) {
                    return;
                }
                launchTimer.stop();
                const launch = tasks.pendingLaunch;
                tasks.pendingLaunch = null;
                tasks.pendingLaunchDesktop = "";
                tasks.pendingLaunchTries = 0;
                if (launch) {
                    launch();
                }
            }
        }

        // fork: обновление имён рабочих столов (см. комментарий у tasks.desktopNames).
        // Список от VirtualDesktopInfo может меняться «на месте», поэтому каждый
        // тик делаем обычный JS-массив и сравниваем его с текущей копией.
        Timer {
            id: desktopNamesTimer

            interval: 1000
            repeat: true
            triggeredOnStart: true
            running: tasks.groupByDesktop

            onTriggered: {
                const raw = virtualDesktopInfo.desktopNames;
                const names = [];
                for (let i = 0; i < raw.length; ++i) {
                    names.push(String(raw[i]));
                }
                if (!tasks.desktopNamesEqual(tasks.desktopNames, names)) {
                    tasks.desktopNames = names;
                }
            }
        }

        Timer {
            id: iconGeometryTimer

            interval: 500
            repeat: false

            onTriggered: {
                tasks.publishIconGeometries(tasks.visibleTaskItems(), tasks);
            }
        }

        Binding {
            target: Plasmoid
            property: "status"
            value: (tasksModel.anyTaskDemandsAttention && Plasmoid.configuration.unhideOnAttention
                ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.PassiveStatus)
            restoreMode: Binding.RestoreBinding
        }

        Connections {
            target: Plasmoid.configuration

            function onLaunchersChanged(): void {
                tasksModel.launcherList = Plasmoid.configuration.launchers
            }
            function onGroupingAppIdBlacklistChanged(): void {
                tasksModel.groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            }
            function onGroupingLauncherUrlBlacklistChanged(): void {
                tasksModel.groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;
            }
        }

        Component {
            id: busyIndicator
            PlasmaComponents3.BusyIndicator {}
        }

        // Save drag data
        Item {
            id: dragHelper

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
            Drag.onDragFinished: dropAction => {
                tasks.dragSource = null;
            }
        }

        KSvg.FrameSvgItem {
            id: taskFrame

            visible: false

            imagePath: "widgets/tasks"
            prefix: TaskTools.taskPrefix("normal", Plasmoid.location)
        }

        MouseHandler {
            id: mouseHandler

            // Форк: прямоугольник апплета в панели может оказаться меньше
            // содержимого (см. Layout.preferredWidth), а область перетаскивания
            // должна совпадать с видимыми группами, иначе drop-события
            // достаются только первым пикселям первой группы.
            x: 0
            y: 0
            width: tasks.groupByDesktop ? taskListHost.width : parent.width
            height: tasks.groupByDesktop ? taskListHost.height : parent.height

            target: tasks.groupByDesktop ? taskListHost : taskList
            childAtProvider: tasks.groupByDesktop ? (x, y) => tasks.taskItemAt(taskListHost, x, y) : null
            // Колесо пока работает только в режиме апстрима: в группах нужен
            // отдельный обход по всем спискам, см. README.
            handleWheelEvents: !tasks.groupByDesktop

            onUrlsDropped: urls => {
                // If all dropped URLs point to application desktop files, we'll add a launcher for each of them.
                const createLaunchers = urls.every(item => backend.isApplication(item));

                if (createLaunchers) {
                    urls.forEach(item => addLauncher(item));
                    return;
                }

                if (!hoveredItem) {
                    return;
                }

                // Otherwise we'll just start a new instance of the application with the URLs as argument,
                // as you probably don't expect some of your files to open in the app and others to spawn launchers.
                (hoveredItem.taskModel || tasksModel).requestOpenUrls(hoveredItem.modelIndex(), urls);
            }
        }

        ToolTipDelegate {
            id: openWindowToolTipDelegate
            visible: false
        }

        ToolTipDelegate {
            id: pinnedAppToolTipDelegate
            visible: false
        }

        TriangleMouseFilter {
            id: tmf
            filterTimeOut: 300
            active: tasks.toolTipAreaItem && tasks.toolTipAreaItem.toolTipOpen
            blockFirstEnter: false

            edge: {
                switch (Plasmoid.location) {
                case PlasmaCore.Types.BottomEdge:
                    return Qt.TopEdge;
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge;
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge;
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge;
                default:
                    return Qt.TopEdge;
                }
            }

            LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Qt.application.layoutDirection, vertical)
            anchors {
                left: parent.left
                top: parent.top
            }

            height: taskListHost.height
            width: taskListHost.width

            Item {
                id: taskListHost

                anchors {
                    left: parent.left
                    top: parent.top
                }

                // Лишние группы не должны «вылезать» на соседние виджеты панели.
                clip: tasks.groupByDesktop

                width: tasks.groupByDesktop ? groupsRow.width : taskList.width
                height: tasks.groupByDesktop ? groupsRow.height : taskList.height

                // --- режим апстрима: один общий список задач ---------------
                TaskList {
                    id: taskList

                    tasksRoot: tasks
                    taskModel: tasksModel
                    visible: !tasks.groupByDesktop

                    anchors {
                        left: parent.left
                        top: parent.top
                    }

                    LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Qt.application.layoutDirection, vertical)

                    onAnimatingChanged: {
                        if (!animating) {
                            tasks.publishIconGeometries(children, tasks);
                        }
                    }

                    Repeater {
                        id: taskRepeater

                        delegate: Task {
                            tasksRoot: tasks
                            taskModel: tasksModel
                            taskList: tasks.taskList
                        }
                        onItemRemoved: (index, item) => {
                            if (tasks.containsMouse && index !== taskRepeater.count &&
                                item.model.WinIdList.length > 0 &&
                                taskClosedWithMouseMiddleButton.includes(item.winIdList[0])) {
                                needLayoutRefresh = true;
                            }
                            taskClosedWithMouseMiddleButton = [];
                        }
                    }
                }

                // --- режим форка: [подпись стола | его иконки] на каждый стол ---
                Grid {
                    id: groupsRow

                    visible: tasks.groupByDesktop

                    anchors {
                        left: parent.left
                        top: parent.top
                    }

                    flow: tasks.vertical ? Grid.TopToBottom : Grid.LeftToRight
                    spacing: 1

                    Repeater {
                        id: desktopGroupRepeater

                        model: tasks.groupByDesktop ? virtualDesktopInfo.desktopIds : []

                        delegate: Item {
                            id: groupRoot

                            required property int index
                            required property var modelData

                            readonly property Item list: groupList
                            readonly property bool current: modelData === virtualDesktopInfo.currentDesktop

                            // Место под разделитель между группами.
                            readonly property int separatorWidth: index > 0 ? 3 : 0

                            // Пустые столы тоже показываем: подпись группы — это и есть
                            // индикатор рабочих столов.
                            width: content.width + separatorWidth
                            height: content.height

                            // Модель именно этого рабочего стола.
                            TaskManager.TasksModel {
                                id: groupModel

                                virtualDesktop: groupRoot.modelData
                                filterByVirtualDesktop: true
                                filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen
                                filterByActivity: Plasmoid.configuration.showOnlyCurrentActivity
                                activity: activityInfo.currentActivity
                                screenGeometry: Plasmoid.containment.screenGeometry

                                // fork: закрепления хранятся за конкретным столом
                                // (конфиг launcherDesktops), список по умолчанию пуст.
                                launcherList: tasks.launchersFor(groupRoot.modelData, tasks.launcherDesktops)

                                sortMode: tasksModel.sortMode
                                groupMode: tasksModel.groupMode
                                groupInline: tasksModel.groupInline
                                separateLaunchers: tasksModel.separateLaunchers
                                launchInPlace: tasksModel.launchInPlace
                                hideActivatedLaunchers: tasksModel.hideActivatedLaunchers
                                groupingWindowTasksThreshold: tasksModel.groupingWindowTasksThreshold
                                groupingAppIdBlacklist: tasksModel.groupingAppIdBlacklist
                                groupingLauncherUrlBlacklist: tasksModel.groupingLauncherUrlBlacklist
                            }

                            Rectangle {
                                visible: groupRoot.separatorWidth > 0
                                width: 1
                                height: Math.round(groupRoot.height * 0.6)
                                y: Math.round((groupRoot.height - height) / 2)
                                color: Kirigami.Theme.disabledTextColor
                                opacity: 0.5
                            }

                            // Подпись стола + его иконки.
                            Grid {
                                id: content

                                x: groupRoot.separatorWidth
                                y: 0

                                flow: tasks.vertical ? Grid.TopToBottom : Grid.LeftToRight

                                DesktopHeader {
                                    desktopName: tasks.desktopLabel(groupRoot.index, tasks.desktopNames)
                                    current: groupRoot.current
                                    dropTarget: tasks.dragOverGroup === groupRoot
                                    tasksRoot: tasks
                                    onActivated: tasks.switchToDesktop(groupRoot.index)
                                }

                                TaskList {
                                    id: groupList

                                    tasksRoot: tasks
                                    taskModel: groupModel
                                    clampToWidget: false

                                    LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Qt.application.layoutDirection, vertical)

                                    onAnimatingChanged: {
                                        if (!animating) {
                                            tasks.publishIconGeometries(children, tasks);
                                        }
                                    }

                                    Repeater {
                                        model: groupModel

                                        delegate: Task {
                                            tasksRoot: tasks
                                            taskModel: groupModel
                                            taskList: groupList

                                            // Пока приложение запускается, окна ещё нет и
                                            // стартовая задача не знает своего стола
                                            // (VirtualDesktops=[0], IsOnAllVirtualDesktops),
                                            // поэтому во всех моделях она есть. Показываем
                                            // её только в группе текущего стола — там, где
                                            // появится окно (collapsed ещё и обнуляет место,
                                            // которое иначе резервирует GridLayout).
                                            collapsed: !groupRoot.current && model && model.IsStartup === true
                                            visible: !collapsed
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property Component groupDialogComponent: Qt.createComponent("GroupDialog.qml")
    property GroupDialog groupDialog

    readonly property bool supportsLaunchers: true

    // fork: в режиме групп «закрепить» = закрепить за текущим столом
    // (drag-n-drop .desktop на виджет и запросы извне идут сюда).
    function hasLauncher(url: url): bool {
        if (tasks.groupByDesktop) {
            return tasks.hasLauncherOnDesktop(url, virtualDesktopInfo.currentDesktop, tasks.launcherDesktops);
        }
        return tasksModel.launcherPosition(url) !== -1;
    }

    function addLauncher(url: url): void {
        if (Plasmoid.immutability === PlasmaCore.Types.SystemImmutable) {
            return;
        }
        if (tasks.groupByDesktop) {
            tasks.addLauncherToDesktop(url, virtualDesktopInfo.currentDesktop);
            return;
        }
        tasksModel.requestAddLauncher(url);
    }

    function removeLauncher(url: url): void {
        if (Plasmoid.immutability === PlasmaCore.Types.SystemImmutable) {
            return;
        }
        if (tasks.groupByDesktop) {
            tasks.removeLauncherFromDesktop(url, virtualDesktopInfo.currentDesktop);
            return;
        }
        tasksModel.requestRemoveLauncher(url);
    }

    // This is called by plasmashell in response to a Meta+number shortcut
    // (ShellCorona::activateTaskManagerEntry, индекс 0-based).
    // В режиме групп нумерация — в рамках текущего рабочего стола.
    function activateTaskAtIndex(index: var): void {
        if (typeof index !== "number") {
            return;
        }

        const task = tasks.currentDesktopTaskItems()[index];
        if (task) {
            TaskTools.activateTask(task.modelIndex(), task.model, null, task, Plasmoid, this, effectWatcher.registered, task.taskModel);
        }
    }

    function createContextMenu(rootTask, modelIndex, args = {}) {
        const initialArgs = Object.assign(args, {
            visualParent: rootTask,
            modelIndex,
            taskModel: rootTask?.taskModel ?? tasksModel,
            mpris2Source,
            backend,
        });
        return contextMenuComponent.createObject(rootTask, initialArgs);
    }

    function switchToDesktop(index: int): void {
        if (index >= 0 && index < virtualDesktopInfo.desktopIds.length) {
            desktopPagerModel.changePage(index);
        }
    }

    function shouldBeMirrored(reverseMode, layoutDirection, vertical): bool {
        // LayoutMirroring is only horizontal
        if (vertical) {
            return layoutDirection === Qt.RightToLeft;
        }

        if (layoutDirection === Qt.LeftToRight) {
            return reverseMode;
        }
        return !reverseMode;
    }

    Component.onCompleted: {
        TaskTools.taskManagerInstanceCount += 1;
        requestLayout.connect(iconGeometryTimer.restart);
        windowsHovered.connect(backend.windowsHovered);
        activateWindowView.connect(backend.activateWindowView);
        tasks.dndLog("geom tasks=" + Math.round(tasks.width) + "x" + Math.round(tasks.height)
            + " mouse=" + Math.round(mouseHandler.width) + "x" + Math.round(mouseHandler.height)
            + " host=" + Math.round(taskListHost.width) + "x" + Math.round(taskListHost.height)
            + " grid=" + Math.round(groupsRow.width)
            + " fill=" + Plasmoid.configuration.fill
            + " group=" + Plasmoid.configuration.groupByDesktop
            + " ff=" + tasks.Plasmoid.formFactor
            + " v=" + tasks.vertical);
    }

    Component.onDestruction: {
        TaskTools.taskManagerInstanceCount -= 1;
    }
}
