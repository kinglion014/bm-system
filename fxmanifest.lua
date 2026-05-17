fx_version 'cerulean'
game 'gta5'

author 'BLDR'
description 'Black Market / Underground Economy System'
version '1.0.0'

lua54 'yes'

dependencies {
    '/server:5181',
    'ox_lib',
    'ox_target',
    'ox_inventory'
}

shared_scripts {
    'config.lua',
    'shared/main.lua'
}

client_scripts {
    'client/blackmarket.lua',
    'client/trading.lua',
    'client/police.lua'
}

server_scripts {
    '@ox_lib/init.lua',
    'server/logs.lua',
    'server/stock.lua',
    'server/reputation.lua',
    'server/trading.lua',
    'server/main.lua'
}
