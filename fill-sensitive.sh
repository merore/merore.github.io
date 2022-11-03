#!/bin/bash

if [ -f .sensitive ]; then
    . .sensitive
fi

CONFIG_FILE=_config.shoka.yml

function fill()
{
sed -i "s/VALINE_APP_ID/$VALINE_APP_ID/" $CONFIG_FILE
sed -i "s/VALINE_APP_KEY/$VALINE_APP_KEY/" $CONFIG_FILE
}

function restore()
{
sed -i "s/$VALINE_APP_ID/VALINE_APP_ID/" $CONFIG_FILE
sed -i "s/$VALINE_APP_KEY/VALINE_APP_KEY/" $CONFIG_FILE
}


if [ $1 == 'restore' ]; then
    restore
fi

if [ $1 == 'fill' ]; then
    fill
fi
