#!/bin/bash

icon_path="$HOME/.config/hypr/icons/media-record.svg"
notify_cmd_shot="notify-send -h string:x-canonical-private-synchronous:screencord -u low -i ${icon_path}"

recordings="$HOME/Videos/Recordings"
tmp_dir="${recordings}/.tmp"
tmp_file="${tmp_dir}/.recording"

if [ -n "$(pgrep wf-recorder)" ]; then
    killall -s SIGINT wf-recorder
    # Wait for wf-recorder to exit
    while pgrep -x wf-recorder > /dev/null 2>&1; do sleep 0.2; done
    pkill -RTMIN+8 waybar

    if [ -f "${tmp_file}" ]; then
        tmp_file="$(cat "${tmp_file}")"
        filename="Record_$(date "+%s").mp4"
        filepath="${recordings}/${filename}"
        saved_to="${recordings}/${filename}"

        mv "${tmp_file}" "${filepath}"

        action=$($notify_cmd_shot "Screen Record" "Saved to ${saved_to}" --action " Open containing folder")

        if [[ "${action}" == "0" ]]; then
            thunar "${filepath}"
        fi
    fi
else
    ${notify_cmd_shot} "Screen Record" "Not recording!"
fi
