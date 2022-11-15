#!/bin/bash

THEME_CONFIG_FILE=_config.shoka.yml
CONFIG_FILE=_config.yml

if [[ -f .private ]]; then
    . .private
fi

function replacevar()
{
    sed -i "s/$1/$2/" $3
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
checkvar BAIDU_SEO_TOKEN $BAIDU_SEO_TOKEN
checkvar ALGOLIA_APP_ID $ALGOLIA_APP_ID
checkvar ALGOLIA_API_KEY $ALGOLIA_API_KEY
checkvar ALGOLIA_ADMIN_API_KEY $ALGOLIA_ADMIN_API_KEY

replacevar VALINE_APP_ID $VALINE_APP_ID $THEME_CONFIG_FILE
replacevar VALINE_APP_KEY $VALINE_APP_KEY $THEME_CONFIG_FILE
replacevar BAIDU_SEO_TOKEN $BAIDU_SEO_TOKEN $CONFIG_FILE

replacevar ALGOLIA_APP_ID $ALGOLIA_APP_ID $CONFIG_FILE
replacevar ALGOLIA_API_KEY $ALGOLIA_API_KEY $CONFIG_FILE
replacevar ALGOLIA_ADMIN_API_KEY $ALGOLIA_ADMIN_API_KEY $CONFIG_FILE
