# Sauf-O-Mat

A Flutter project for a carneval music club's event where the bought drinks shall be displayed. This is for a contest of which group drinks the most

The video server is hosted on my vServer: 
- check logs: pm2 logs saufomatWebsocket
- check status of server: pm2 list


## Before starting the app

Start the websocket for video transfer
    - server account: sarah
    - cd saufomat
    - pm2 start server.js --name saufomatWebsocket
    - pm2 save
    