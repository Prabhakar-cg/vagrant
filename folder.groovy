folder('artemis') {
    displayName('Artemis')
    description('Artemis mission')
}
folder('artemis/newmoon') {
    displayName('New Moon')
}
folder('artemis/waxingcrescent') {
    displayName('Waxing Crescent')
}
folder('artemis/firstquarter') {
    displayName('First Quarter')
}
folder('artemis/waxinggibbous') {
    displayName('Waxing Gibbous')
}

folder('Artemis') {
    authorization {
        permission('hudson.model.Item.Create:authenticated')
        permission('voyager', [
                'hudson.model.Item.Create',
                'hudson.model.Item.Discover'
                ])
    }
}