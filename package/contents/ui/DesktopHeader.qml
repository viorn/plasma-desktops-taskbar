/*
    SPDX-FileCopyrightText: 2026 fork authors
    SPDX-License-Identifier: GPL-2.0-or-later

    Подпись группы задач — название виртуального рабочего стола
    («00», «Работа», …). Стоит в начале своей группы, поэтому сразу видно,
    какие приложения открыты именно на этом столе.

    Клик по подписи переключает на этот рабочий стол.
*/

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: header

    required property var tasksRoot
    required property string desktopName
    required property bool current
    // Форк: сюда тащат задачу из другой группы — подсвечиваем стол-получатель.
    property bool dropTarget: false

    signal activated()

    // Толщина панели: в горизонтальной это высота, в вертикальной — ширина.
    // Считаем от tasksRoot, а не от собственных размеров, иначе получится
    // binding loop «размер → шрифт → размер».
    readonly property real thickness: header.tasksRoot.vertical
        ? header.tasksRoot.width
        : header.tasksRoot.height
    readonly property real fontSize: Math.max(Kirigami.Units.smallSpacing * 2,
        Math.min(Math.round(header.thickness * 0.42), Math.round(Kirigami.Units.gridUnit * 1.6)))

    implicitWidth: header.tasksRoot.vertical
        ? header.tasksRoot.width
        : Math.max(label.implicitWidth + Kirigami.Units.smallSpacing * 2, Math.round(Kirigami.Units.gridUnit * 0.9))
    implicitHeight: header.tasksRoot.vertical
        ? Math.round(label.implicitHeight + Kirigami.Units.smallSpacing)
        : header.tasksRoot.height

    width: implicitWidth
    height: implicitHeight

    // Подсветка текущего рабочего стола.
    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(Kirigami.Units.smallSpacing / 2)
        radius: Kirigami.Units.smallSpacing
        color: Kirigami.Theme.highlightColor
        opacity: header.dropTarget ? 0.45 : (header.current ? 0.3 : 0)
    }

    Text {
        id: label

        anchors.centerIn: parent

        text: header.desktopName
        font.pixelSize: header.fontSize
        font.bold: header.current
        color: header.current ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        opacity: header.current ? 1 : 0.6
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: header.activated()
    }
}
