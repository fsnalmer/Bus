fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'esx_bus'
description 'Service de transport en commun'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@es_extended/imports.lua',
    'server/main.lua'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target'
}
