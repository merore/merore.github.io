#!/bin/bash

CONFIG_FILE=_config.shoka.yml

function replacevar()
{
    sed -i "s/$1/$2/" $CONFIG_FILE
}

function checkvar()
{
    if [[ $2 == '' ]]; then
        echo "Please set $1 to your environment."
        exit 1
    fi
}

checkvar VALINE_APP_ID $VALINE_APP_ID
checkvar VALINE_APP_KEY $VALINE_APP_KEY

replacevar VALINE_APP_ID $VALINE_APP_ID
replacevar VALINE_APP_KEY $VALINE_APP_KEY
