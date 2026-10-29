"""Verify exact exported assets in the disposable Vyoora QA simulator only.

Read-only host verification preserves the app's add-only Photos permission.
Never points at a physical device, Mac Photos library, or an existing simulator.
"""
import argparse
import json
import re
from pathlib import Path
import sqlite3
import subprocess
from PIL import Image

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device',required=True)
parser.add_argument('--test-log',type=Path,required=True)
args=parser.parse_args()
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j']))['devices']
device=next((d for values in devices.values() for d in values if d['udid']==args.device),None)
assert device and device['name']=='Vyoora QA','Only the disposable Vyoora QA simulator may be inspected'
proof={'assets':re.findall(r'VYOORA_NATIVE_PHOTO_ASSET_ID=([^\s]+)',args.test_log.read_text())}
assert proof['assets']
media=Path.home()/'Library/Developer/CoreSimulator/Devices'/args.device/'data/Media'
database=media/'PhotoData/Photos.sqlite'
db=sqlite3.connect(database.as_uri()+'?mode=ro',uri=True)
results=[]
for index,identifier in enumerate(proof['assets']):
    uuid=identifier.split('/')[0]
    row=db.execute('SELECT ZDIRECTORY,ZFILENAME,ZWIDTH,ZHEIGHT FROM ZASSET WHERE lower(ZUUID)=lower(?)',(uuid,)).fetchone()
    assert row,'Exported asset was not found in Photos'
    path=media/row[0]/row[1]
    assert path.is_file(),'Photos asset file is missing'
    with Image.open(path) as image:
        image.load();assert image.size==(row[2],row[3])
        if index==0:
            assert image.size==(800,1200)
            pixel=image.convert('RGB').getpixel((100,100))
            assert all(abs(a-b)<=4 for a,b in zip(pixel,(30,60,90)))
            footer=image.convert('RGB').crop((300,1100,800,1200))
            assert sum(min(p)>140 for p in footer.getdata())>30,'Visible watermark pixels missing from the Photos file'
        results.append({'existsInPhotos':True,'width':image.width,'height':image.height})
db.close()
print(json.dumps({'photosVerified':True,'watermarkPixelsVerified':True,'assets':results},indent=2))
