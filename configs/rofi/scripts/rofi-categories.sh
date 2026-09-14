#!/bin/bash
state_file="/tmp/rofi-cat-state"

show_categories() {
    printf '\0prompt\x1f \n'
    printf '\0theme\x1flistview { columns: 4; fixed-columns: true; } element { padding: 6px; }\n'
    printf 'AudioVideo\0icon\x1fapplications-multimedia\n'
    printf 'Development\0icon\x1fapplications-engineering\n'
    printf 'Education\0icon\x1faccessories-dictionary\n'
    printf 'Game\0icon\x1fapplications-games\n'
    printf 'Graphics\0icon\x1fapplications-graphics\n'
    printf 'Network\0icon\x1fnetwork-workgroup\n'
    printf 'Office\0icon\x1fapplications-office\n'
    printf 'Settings\0icon\x1fpreferences-system\n'
    printf 'System\0icon\x1femblem-system\n'
    printf 'Utility\0icon\x1fapplications-utilities\n'
}

if [ "$ROFI_RETV" = "0" ]; then
    show_categories
    exit 0
fi

if [ ! -f "$state_file" ]; then
    echo "$1" > "$state_file"
    printf '\0prompt\x1f%s\n' "$1"
    printf '← Back\n'
    for dir in /usr/share/applications "$HOME/.local/share/applications"; do
        [ -d "$dir" ] || continue
        for file in "$dir"/*.desktop; do
            [ -f "$file" ] || continue
            grep -qi "^NoDisplay=true" "$file" && continue
            grep -qi "^Categories=.*;$1;.*" "$file" || continue
            name=$(grep -i "^Name=" "$file" | head -1 | cut -d= -f2-)
            exec_cmd=$(grep -i "^Exec=" "$file" | head -1 | cut -d= -f2- | sed 's/%[a-zA-Z]//g')
            icon=$(grep -i "^Icon=" "$file" | head -1 | cut -d= -f2-)
            [ -n "$name" ] && printf '%s\0icon\x1f%s\0info\x1f%s\n' "$name" "$icon" "$exec_cmd"
        done
    done
    exit 0
fi

selected="$1"
if [ "$selected" = "← Back" ]; then
    rm -f "$state_file"
    show_categories
    exit 0
fi

rm -f "$state_file"
if [ -n "$ROFI_INFO" ]; then
    coproc ( sh -c "$ROFI_INFO" > /dev/null 2>&1 )
fi
