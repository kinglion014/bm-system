-- Add these entries to ox_inventory/data/items.lua inside the returned table.
-- Weapon entries used by this resource already live in ox_inventory/data/weapons.lua.
-- This server already has lockpick, meth, oxy, and radio in ox_inventory/data/items.lua.

['weed_bag'] = {
    label = 'Weed Bag',
    weight = 100,
    stack = true
},

['cocaine'] = {
    label = 'Cocaine',
    weight = 100,
    stack = true
},

['stolen_phone'] = {
    label = 'Stolen Phone',
    weight = 190,
    stack = true
},

['stolen_jewelry'] = {
    label = 'Stolen Jewelry',
    weight = 250,
    stack = true
},

['stolen_laptop'] = {
    label = 'Stolen Laptop',
    weight = 2000,
    stack = true
},

['stolen_watch'] = {
    label = 'Luxury Watch',
    weight = 300,
    stack = true
},

['armor'] = {
    label = 'Body Armor',
    weight = 3000,
    stack = false,
    client = {
        anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d' },
        usetime = 3500
    }
},
