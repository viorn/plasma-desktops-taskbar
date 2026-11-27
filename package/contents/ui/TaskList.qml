/*
    SPDX-FileCopyrightText: 2012-2013 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 fork authors

    SPDX-License-Identifier: GPL-2.0-or-later

    Один список задач. В форке их несколько: либо один общий (как в апстриме),
    либо по одному на каждый виртуальный рабочий стол. Поэтому все внешние
    зависимости приходят через свойства, а не через id из main.qml.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import "code/layoutmetrics.js" as LayoutMetrics

GridLayout {
    id: taskListView

    // Модель именно этого списка (TaskManager.TasksModel).
    required property var taskModel
    // Корневой объект виджета (main.qml), нужен для геометрии и настроек.
    required property var tasksRoot

    property bool animating: false

    // В режиме групп по столам список не должен зависеть от общего размера
    // виджета (иначе получаем цикл биндингов width/height ↔ preferred size).
    property bool clampToWidget: true

    rowSpacing: 0
    columnSpacing: 0

    readonly property int taskCount: taskModel ? taskModel.count : 0

    readonly property real widthOccupation: taskCount / Math.max(1, columns)
    readonly property real heightOccupation: taskCount / Math.max(1, rows)

    property int animationsRunning: 0
    onAnimationsRunningChanged: {
        animating = animationsRunning > 0;
    }

    readonly property real minimumWidth: children
        .filter(item => item.visible && item.width > 0)
        .reduce((minimumWidth, item) => Math.min(minimumWidth, item.width), Infinity)

    readonly property int stripeCount: {
        if (tasksRoot.plasmoid.configuration.maxStripes === 1) {
            return 1;
        }

        // Пустой список (например, пустой рабочий стол) — нечего раскладывать.
        if (children.length === 0) {
            return 1;
        }

        // The maximum number of stripes allowed by the applet's size
        const stripeSizeLimit = tasksRoot.vertical
            ? Math.floor(tasksRoot.width / children[0].implicitWidth)
            : Math.floor(tasksRoot.height / children[0].implicitHeight)
        const maxStripes = Math.max(1, Math.min(tasksRoot.plasmoid.configuration.maxStripes, stripeSizeLimit))

        if (tasksRoot.plasmoid.configuration.forceStripes) {
            return maxStripes;
        }

        // The number of tasks that will fill a "stripe" before starting the next one
        const maxTasksPerStripe = tasksRoot.vertical
            ? Math.max(1, Math.ceil(tasksRoot.height / LayoutMetrics.preferredMinHeight()))
            : Math.max(1, Math.ceil(tasksRoot.width / LayoutMetrics.preferredMinWidth()))

        return Math.max(1, Math.min(Math.ceil(taskCount / maxTasksPerStripe), maxStripes))
    }

    readonly property int orthogonalCount: {
        return Math.ceil(taskCount / stripeCount);
    }

    rows: Math.max(1, tasksRoot.vertical ? orthogonalCount : stripeCount)
    columns: Math.max(1, tasksRoot.vertical ? stripeCount : orthogonalCount)

    // Размеры списка. В апстриме это жило в main.qml — здесь, чтобы одинаково
    // работать и для единственного списка, и для группы на каждый стол.
    Layout.maximumWidth: {
        if (taskCount === 0) {
            return 0;
        }
        const totalMaxWidth = children.reduce((accumulator, child) => {
            if (!isFinite(child.Layout.maximumWidth)) {
                return accumulator;
            }
            return accumulator + child.Layout.maximumWidth;
        }, 0);
        return Math.round(totalMaxWidth / widthOccupation);
    }
    Layout.maximumHeight: {
        if (taskCount === 0) {
            return 0;
        }
        const totalMaxHeight = children.reduce((accumulator, child) => {
            if (!isFinite(child.Layout.maximumHeight)) {
                return accumulator;
            }
            return accumulator + child.Layout.maximumHeight;
        }, 0);
        return Math.round(totalMaxHeight / heightOccupation);
    }
    width: {
        if (taskCount === 0 || tasksRoot.shouldShrinkToZero) {
            return 0;
        }
        if (!clampToWidget) {
            return Layout.maximumWidth;
        }
        if (tasksRoot.vertical) {
            return tasksRoot.width * Math.min(1, widthOccupation);
        }
        return Math.min(tasksRoot.width, Layout.maximumWidth);
    }
    height: {
        if (taskCount === 0) {
            return 0;
        }
        if (!clampToWidget) {
            // Группа задач: в горизонтальной панели тянемся на всю высоту
            // виджета, в вертикальной — по содержимому (Layout.maximumHeight).
            return tasksRoot.vertical ? Layout.maximumHeight : tasksRoot.height;
        }
        if (tasksRoot.shouldShrinkToZero) {
            return 0;
        }
        if (tasksRoot.vertical) {
            return Math.min(tasksRoot.height, Layout.maximumHeight);
        }
        return tasksRoot.height * Math.min(1, heightOccupation);
    }

    flow: {
        if (tasksRoot.vertical) {
            return tasksRoot.plasmoid.configuration.forceStripes ? Grid.LeftToRight : Grid.TopToBottom;
        }
        return tasksRoot.plasmoid.configuration.forceStripes ? Grid.TopToBottom : Grid.LeftToRight;
    }
}
