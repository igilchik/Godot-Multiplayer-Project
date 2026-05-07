# 2D Top-Down Multiplayer Game (Godot 4.6 + ENet)

A small **2D top-down multiplayer arena prototype** built in **Godot 4.6** using  
**ENet** and **Godot MultiplayerAPI**.

Players can create a lobby (Host) or join an existing lobby (Client), then the Host starts the match.  
The project focuses on a stable lobby-to-match flow, correct player spawning/authority, and synchronized gameplay state.

---

## Features (Short)
- Host/Client multiplayer lobby
- Nickname support in lobby player list
- Scene switching: **Main Menu → Game**
- Server-side player spawning with correct authority
- Synchronized coin pickups (collected coins disappear for all players)
- Windows build testing (local + LAN / mobile hotspot)

---

## Gameplay (Short Description)

The game is a top-down arena match where players try to win either by defeating opponents or by collecting more coins than others. Coins are placed around the map and can be collected during the match. Players also fight using a melee sword attack.

Coins are used for weapon upgrades. Upgrading the sword increases the player’s damage. The first upgrade costs **10 coins** and the second upgrade costs **15 coins**. Even if a player spends coins on upgrades during the match, the final result is still based on the **total number of coins collected** during the match (spent coins are still counted as collected).

Match duration depends on how many players joined:
- If only **1 player** joined, the match lasts **2 minutes** and ends when the timer runs out.
- If **2 or more players** joined, the match lasts **3 minutes** and can end earlier if only one player remains alive. If the timer ends while multiple players are still alive, the winner is the player with the **highest total coins collected**.

After the match ends, players can either start a new match (rematch) or return to the main menu.

To make gameplay clear, the game includes animations for the player (idle, running, death) and weapon effects (sword swing and air slash).

---

## How to Connect Online (LAN / Mobile Hotspot)

This project uses **direct IP connection** (ENet).  
To play together, both players must be on the **same local network**, for example:
- **Private / Home network**
- **Mobile hotspot network**

> Do **NOT** use a **Public network** for testing local multiplayer.  
> Public network policies may block or restrict local device-to-device connections.

---

## Firewall and Network Security (Windows)

For local testing, make sure Windows Firewall does not block connections.  
Disable firewall for:
- Domain network
- Private network
- Public network

### Disable Windows Firewall (all 3 profiles)
1. Press **Win**, type **Windows Security**, open it
2. Go to **Firewall & network protection**
3. Open **Domain network** → turn **Microsoft Defender Firewall** **Off**
4. Go back, open **Private network** → turn it **Off**
5. Go back, open **Public network** → turn it **Off**

> ⚠️ Disabling firewall reduces protection. Use it only for local testing in a trusted environment.

---

## Host Setup (Player A)

1. Start the game
2. Enter your **Nickname**
3. Set:
   - **IP**: `0.0.0.0`
   - **Port**: `7777` or `7778`
4. Click **HOST**

Important:
- The host chooses the port.
- All clients must use the **same port**.

---

## Find the Host IPv4 Address (Windows)

The client must connect using the host **local IPv4 address**.

On the host PC:
1. Press **Win + R**
2. Type `cmd` and press **Enter**
3. Run: ipconfig
4. Find the active adapter (Wi-Fi / Ethernet) and copy:
   IPv4 Address (example: 192.168.43.120)

Client Setup (Player B)
1. Start the game
2. Enter your Nickname
3. Set:
   - IP: the host IPv4 address found using ipconfig
   - Port: exactly the same port as the host (7777 or 7778)
4. Click JOIN

Starting the Match
When both players are in the lobby:
- Only the host can start the match
- The client must wait until the host clicks Start Match

Example Connection Values

Host:
- IP: 0.0.0.0
- Port: 7778
- Action: click HOST

Client:
- IP: 192.168.43.120 (example host IPv4)
- Port: 7778
- Action: click JOIN

Troubleshooting

Client cannot connect — check that:
- both PCs are connected to the same network (same Wi-Fi or same mobile hotspot)
- the network is Private/Home or mobile hotspot, not Public
- firewall restrictions are disabled (or the game is allowed in firewall)
- the client entered the correct host IPv4 from ipconfig
- the client uses the same port as the host

127.0.0.1 works only on one PC:
- 127.0.0.1 is localhost. It works only if host and client run on the same computer.

Port mismatch:
- If host uses 7778, the client must also use 7778.

License
This project is a student prototype for educational purposes.
