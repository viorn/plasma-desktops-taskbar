/*
    SPDX-FileCopyrightText: 2026 fork authors
    SPDX-License-Identifier: GPL-2.0-or-later

    Индикатор-пейджер виртуальных рабочих столов: чипы с именами столов
    («00», «01», …), подсветка текущего и переключение по клику.

    Переключение сделано через PagerModel.changePage(), который использует сам
    апплет «Пейджер» — отдельного D-Bus вызова не требуется.
*/

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.pager as Pager

Grid {
    id: pager

    required property var tasksRoot

    flow: tasksRoot.vertical ? Grid.TopToBottom : Grid.LeftToRight
    spacing: 1

    Pager.PagerModel {
        id: pagerModel
        // Без enabled модель пуста (count = 0) — так устроен PagerModel.
        enabled: pager.visible
        pagerType: Pager.PagerModel.VirtualDesktops
        screenGeometry: pager.tasksRoot.plasmoid.containment.screenGeometry
    }

    Repeater {
        model: pagerModel

        delegate: Item {
            id: chip

            required property int index
            required property var model

            readonly property bool current: index === pagerModel.currentPage
            readonly property int chipThickness: Math.max(Kirigami.Units.gridUnit, Math.round(pager.tasksRoot.height * 0.5))

            // В горизонтальной панели чип тянется по высоте, в вертикальной — по ширине.
            implicitWidth: pager.tasksRoot.vertical ? Math.round(pager.tasksRoot.width * 0.75) : Math.max(chipLabel.implicitWidth + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit)
            implicitHeight: pager.tasksRoot.vertical ? Math.max(chipLabel.implicitHeight + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit) : pager.tasksRoot.height
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing
                color: chip.current ? Kirigami.Theme.highlightColor : "transparent"
                opacity: chip.current ? 0.35 : 0
            }

            Text {
                id: chipLabel
                anchors.centerIn: parent
                text: chip.model ? chip.model.display : ""
                font.pixelSize: Math.max(Kirigami.Units.smallSpacing * 2, Math.round(parent.height * 0.45))
                font.bold: chip.current
                color: chip.current ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                opacity: chip.current ? 1 : 0.7
            }

            MouseArea {
                anchors.fill: parent
                onClicked: pagerModel.changePage(chip.index)
            }
        }
    }
}
