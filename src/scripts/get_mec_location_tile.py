import sys
import json
from requests import get
from pygeotile.tile import Tile

zoom = int(sys.argv[1])

ip = get('https://api.ipify.org').text
ip_info = json.loads(get('https://ipinfo.io/' + ip).text)
location = [float(i) for i in ip_info.get('loc').split(',')]
quadkey = Tile.for_latitude_longitude(location[0],location[1],zoom).quad_tree

print(quadkey)

#curl -s https://ipinfo.io/$(curl -s ifconfig.me) | jq '.loc'