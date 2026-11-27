/*
    SPDX-FileCopyrightText: 2026 the fork authors
    SPDX-License-Identifier: GPL-2.0-or-later

    Единственное место, где зашито «кто мы такие».

    В апстриме «только иконки» — это отдельный пакет org.kde.plasma.icontasks,
    и код проверяет Plasmoid.pluginName === "org.kde.plasma.icontasks" в десятке
    мест. У форка свои Id, поэтому все проверки идут через isIconsOnly():
    меняешь Id в metadata.json — правишь только эти константы.
*/

.pragma library

// Id пакетов этого форка (должны совпадать с metadata.json и Makefile).
const PACKAGE_ID = "local.vyuyukin.taskbar";
const ICONS_ONLY_PACKAGE_ID = "local.vyuyukin.iconbar";

// Id апстримных пакетов: оставлены, чтобы этот же QML работал и в системном
// виджете (например, если файл скопируют обратно в /usr).
const UPSTREAM_PACKAGE_ID = "org.kde.plasma.taskmanager";
const UPSTREAM_ICONS_ONLY_PACKAGE_ID = "org.kde.plasma.icontasks";

function isIconsOnly(pluginName) {
    return pluginName === ICONS_ONLY_PACKAGE_ID || pluginName === UPSTREAM_ICONS_ONLY_PACKAGE_ID;
}
