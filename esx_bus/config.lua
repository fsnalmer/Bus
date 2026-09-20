Config = {}

Config.Debug = false

-- Dépôt de bus : point de départ et de fin du service
Config.Depot = {
    ped = {
        model = 'a_m_m_business_01',
        coords = vector4(1044.86, -3149.31, 5.9, 129.87)
    },
    startRadius = 3.0,

    vehicleModel = 'bus',
    vehicleSpawn = vector4(1049.9, -3147.2, 5.9, 129.0),
    spawnCheckRadius = 6.0,

    returnZone = {
        coords = vector3(1049.9, -3147.2, 5.9),
        radius = 10.0
    },

    blip = {
        sprite = 513,
        color = 3,
        scale = 0.8,
        label = 'Dépôt de bus'
    }
}

-- Tolérances et anti-abus
Config.Security = {
    stopRadius = 12.0,            -- rayon de validation par défaut d'un arrêt
    stopRadiusTolerance = 4.0,    -- marge appliquée à la vérification serveur
    maxVehicleDistance = 80.0,    -- distance max joueur/bus avant abandon
    abandonGraceTicks = 4,        -- nombre de contrôles consécutifs avant abandon
    monitorInterval = 3000        -- fréquence du contrôle pendant le service (ms)
}

-- Paramètres par défaut des arrêts (surchageables par arrêt)
Config.StopDefaults = {
    radius = 12.0,
    waitTime = 6000,
    npcCount = 2,
    pay = 35
}

-- Paramètres des PNJ passagers
Config.Npc = {
    models = {
        'a_m_y_business_01', 'a_f_y_business_02', 'a_m_m_business_01',
        'a_f_m_business_02', 'a_m_y_downtown_01', 'a_f_y_tourist_01'
    },
    spawnDistance = 45.0,   -- distance d'apparition avant l'arrivée à l'arrêt
    maxActive = 8           -- nombre maximal de PNJ actifs simultanément
}

-- Compte de versement de la rémunération (compte ESX)
Config.PaymentAccount = 'bank'

-- Lignes de bus. Ajouter une ligne = ajouter une entrée ici.
Config.Lines = {
    [1] = {
        id = 1,
        name = 'Ligne 1',
        description = 'Dépôt - Centre-ville - Rockford - Del Perro',
        stops = {
            { id = 1, name = 'Legion Square',   coords = vector3(215.67, -810.39, 30.71), pay = 40, waitTime = 6000, npcCount = 3 },
            { id = 2, name = 'Mission Row',      coords = vector3(441.85, -982.14, 30.69), pay = 40, waitTime = 6000, npcCount = 2 },
            { id = 3, name = 'Rockford Hills',   coords = vector3(-615.9, -139.5, 37.4),   pay = 55, waitTime = 7000, npcCount = 2 },
            { id = 4, name = 'Del Perro',        coords = vector3(-1497.9, -554.7, 33.7),  pay = 60, waitTime = 7000, npcCount = 3 }
        }
    },
    [2] = {
        id = 2,
        name = 'Ligne 2',
        description = 'Dépôt - Vespucci - La Plage',
        stops = {
            { id = 1, name = 'Vespucci Beach',   coords = vector3(-1180.5, -1520.5, 4.4),  pay = 45, waitTime = 6000, npcCount = 3 },
            { id = 2, name = 'Pier',              coords = vector3(-1850.0, -1226.3, 12.9), pay = 50, waitTime = 6000, npcCount = 2 },
            { id = 3, name = 'Morningwood',       coords = vector3(-1410.2, -463.9, 35.1),  pay = 50, waitTime = 6000, npcCount = 2 }
        }
    }
}

Config.Notifications = {
    already_active      = 'Vous êtes déjà en service.',
    service_started      = 'Votre service a débuté. Choisissez une ligne.',
    depot_occupied       = 'Le dépôt est actuellement occupé, réessayez plus tard.',
    vehicle_spawn_failed = 'Impossible de récupérer un bus pour le moment.',
    line_selected        = 'Ligne sélectionnée. Rendez-vous au premier arrêt.',
    next_stop            = 'Prochain arrêt : %s (%s/%s)',
    stop_validated       = 'Arrêt "%s" validé (%s/%s). Vous avez perçu %s$.',
    stop_wrong_vehicle   = 'Vous devez être au volant de votre bus de service.',
    stop_out_of_order    = 'Cet arrêt ne correspond pas à votre progression.',
    stop_already_paid    = 'Cet arrêt a déjà été validé.',
    last_stop_reached    = 'Vous avez atteint le dernier arrêt de la ligne.',
    return_started       = 'Trajet retour lancé, rendez-vous au dernier arrêt desservi.',
    return_to_depot      = 'Ramenez le bus au dépôt pour terminer votre service.',
    vehicle_lost         = 'Votre bus a été perdu, le service est annulé.',
    service_abandoned    = 'Vous vous êtes trop éloigné de votre bus. Service annulé.',
    service_ended        = 'Service terminé, le bus a été restitué. Bonne journée.',
    return_wrong_vehicle = 'Ce n\'est pas le bus qui vous a été attribué, ou vous n\'êtes pas au volant.',
    invalid_line         = 'Ligne invalide.'
}
