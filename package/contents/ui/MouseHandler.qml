/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasmoid

import "code/tools.js" as TaskTools

DropArea {
    id: dropArea
    signal urlsDropped(var urls)

    property Item target
    // Форк: когда задачи разложены по группам (рабочим столам), под курсором
    // надо искать задачу в разных списках, а не только в target.
    property var childAtProvider: null
    property Item ignoredItem
    property Item hoveredItem
    property bool isGroupDialog: false
    property bool moved: false

    property alias handleWheelEvents: wheelHandler.handleWheelEvents

    // Форк: перетаскиваемая задача запоминается на старте драга — к его концу
    // tasks.dragSource уже обнулён.
    property Item draggedTask

    // Последняя позиция курсора внутри виджета — для диагностики конца драга.
    property real lastX: 0
    property real lastY: 0

    function itemAtPoint(x, y) {
        const provider = dropArea.childAtProvider;
        if (provider) {
            return provider(x, y);
        }
        return dropArea.target ? dropArea.target.childAt(x, y) : null;
    }

    //ignore anything that is neither internal to TaskManager or a URL list
    onEntered: event => {
        tasks.dndLog("entered formats=" + event.formats.join(","));
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
        }
        if (target.animating) { // Not all targets have an animating property
            target.animating = false;
        }
    }

    onPositionChanged: event => {
        if (target.animating) {
            return;
        }

        lastX = event.x;
        lastY = event.y;

        let above;
        if (isGroupDialog) {
            above = target.itemAt(event.x, event.y);
        } else {
            above = dropArea.itemAtPoint(event.x, event.y);
        }

        // Форк: запоминаем, над чем находится перетаскиваемая задача — по этому
        // месту отпускание решает, куда её перенести (см. tasks.finishDrag).
        // Делаем это до проверки на null: над подписью пустого стола задачи нет,
        // но перенести её туда всё равно можно.
        if (tasks.dragSource) {
            const group = tasks.groupAt(dropArea, event.x, event.y);
            if (above !== tasks.dragOverItem || group !== tasks.dragOverGroup) {
                tasks.dndLog("over item=" + (above && above.model ? above.model.AppName : "null")
                    + " group=" + (group ? String(group.modelData).substring(0, 8) : "null"));
            }
            tasks.dragOverItem = above;
            tasks.dragOverGroup = group;
        }

        if (!above) {
            hoveredItem = null;
            activationTimer.stop();

            return;
        }

        // If we're mixing launcher tasks with other tasks and are moving
        // a (small) launcher task across a non-launcher task, don't allow
        // the latter to be the move target twice in a row for a while, as
        // it will naturally be moved underneath the cursor as result of the
        // initial move, due to being far larger than the launcher delegate.
        // TODO: This restriction (minus the timer, which improves things)
        // has been proven out in the EITM fork, but could be improved later
        // by tracking the cursor movement vector and allowing the drag if
        // the movement direction has reversed, establishing user intent to
        // move back.
        if (!Plasmoid.configuration.separateLaunchers
                && tasks.dragSource?.model.IsLauncher
                && !above.model.IsLauncher
                && above === ignoredItem) {
            return;
        } else {
            ignoredItem = null;
        }

        const taskModel = above.taskModel || tasksModel;
        if (tasks.groupByDesktop && tasks.dragSource
                && (tasks.dragSource.model?.IsLauncher
                    || tasks.isPinnedOnSourceDesktop(tasks.dragSource))) {
            // Порядок закреплений: сразу переставляем строку модели (немедленный
            // отклик, как в апстриме, и обновление карты ручной сортировки) и
            // тут же фиксируем порядок в конфиге — иначе libtaskmanager вернёт
            // прежний порядок из launcherList. См. applyPinDragStep().
            if (above === ignoredItem) {
                return;
            }
            if (tasks.applyPinDragStep(tasks.dragSource, above)) {
                ignoredItem = above;
                ignoreItemTimer.restart();
            }
            return;
        }
        if (taskModel.sortMode === TaskManager.TasksModel.SortManual && tasks.dragSource) {
            // Reject drags between different TaskList instances.
            if (tasks.dragSource.parent !== above.parent) {
                return;
            }

            const insertAt = above.index;

            if (tasks.dragSource !== above && tasks.dragSource.index !== insertAt) {
                if (tasks.groupDialog) {
                    taskModel.move(tasks.dragSource.index, insertAt,
                        taskModel.makeModelIndex(tasks.groupDialog.visualParent.index));
                } else {
                    taskModel.move(tasks.dragSource.index, insertAt);
                }

                ignoredItem = above;
                ignoreItemTimer.restart();
            }
        } else if (!tasks.dragSource && hoveredItem !== above) {
            hoveredItem = above;
            activationTimer.restart();
        }
    }

    onExited: {
        tasks.dndLog("exited last=" + Math.round(lastX) + "," + Math.round(lastY)
            + " size=" + Math.round(dropArea.width) + "x" + Math.round(dropArea.height));
        hoveredItem = null;
        activationTimer.stop();
        // Курсор ушёл с виджета — цели для переноса больше нет.
        if (tasks.dragSource) {
            tasks.dragOverItem = null;
            tasks.dragOverGroup = null;
        }
    }

    onDropped: event => {
        // Внутренний drop: применяем сразу (dragSource ещё жив именно в этот
        // момент), а если drop до виджета не дошёл — это сделает обработчик
        // конца драга ниже.
        if (event.formats.indexOf("application/x-orgkdeplasmataskmanager_taskbuttonitem") >= 0) {
            tasks.dndLog("dropped internal formats=" + event.formats.join(","));
            tasks.finishDrag(tasks.dragSource || draggedTask, tasks.dragOverItem, tasks.dragOverGroup);
            event.accepted = false;
            return;
        }

        // Reject plasmoid drops.
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
            return;
        }

        if (event.hasUrls) {
            urlsDropped(event.urls);
            return;
        }
    }

    Connections {
        target: tasks

        function onDragSourceChanged(): void {
            if (!dragSource) {
                ignoredItem = null;
                ignoreItemTimer.stop();
                // Конец перетаскивания: применяем перенос/перестановку (если это
                // уже не сделал onDropped).
                tasks.finishDrag(draggedTask, tasks.dragOverItem, tasks.dragOverGroup);
                draggedTask = null;
            } else {
                draggedTask = dragSource;
                tasks.dragApplied = false;
                tasks.dragPinMovedLive = false;
                tasks.dndLog("drag start app=" + (dragSource.model ? dragSource.model.AppName : "?")
                    + " launcher=" + (dragSource.model ? dragSource.model.IsLauncher : "?"));
            }
        }
    }

    Timer {
        id: ignoreItemTimer

        repeat: false
        interval: 750

        onTriggered: {
            ignoredItem = null;
        }
    }

    Timer {
        id: activationTimer

        interval: 250
        repeat: false

        onTriggered: {
            if (parent.hoveredItem.model.IsGroupParent) {
                TaskTools.createGroupDialog(parent.hoveredItem, tasks);
            } else if (!parent.hoveredItem.model.IsLauncher) {
                (parent.hoveredItem.taskModel || tasksModel).requestActivate(parent.hoveredItem.modelIndex());
            }
        }
    }

    WheelHandler {
        id: wheelHandler

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property bool handleWheelEvents: true

        enabled: handleWheelEvents && Plasmoid.configuration.wheelEnabled

        onWheel: event => {
            // magic number 15 for common "one scroll"
            // See https://doc.qt.io/qt-6/qml-qtquick-wheelhandler.html#rotation-prop
            let increment = 0;
            while (rotation >= 15) {
                rotation -= 15;
                increment++;
            }
            while (rotation <= -15) {
                rotation += 15;
                increment--;
            }
            const anchor = dropArea.itemAtPoint(event.x, event.y);
            while (increment !== 0) {
                TaskTools.activateNextPrevTask(anchor, increment < 0, Plasmoid.configuration.wheelSkipMinimized, tasks);
                increment += (increment < 0) ? 1 : -1;
            }
        }
    }
}
