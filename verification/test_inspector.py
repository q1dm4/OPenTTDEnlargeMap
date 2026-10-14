import json, subprocess, pathlib, zlib, lzma, struct

root = pathlib.Path(__file__).resolve().parent.parent
binary = root / 'launcher-build/save-inspect'
save = root / 'launcher-base/Sadingham-Population/Sadingham-populated-example-2048.sav'
raw = save.read_bytes()
data = zlib.decompress(raw[8:])
expected = dict(width=2048,height=2048,towns=1352,industries=6401)
folder = root / 'launcher-validation/inspector-cases'
folder.mkdir(exist_ok=True)

def run(name, content, okay=True):
    path = folder / name
    path.write_bytes(content)
    result = subprocess.run([binary,path],capture_output=True,text=True,timeout=15)
    if okay:
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout) == expected, result.stdout
    else:
        assert result.returncode != 0 and result.stderr
    print(name, 'passed')

run('zlib.sav',raw)
run('LZMA save with spaces.sav',b'OTTX'+raw[4:8]+lzma.compress(data))
run('uncompressed.sav',b'OTTN'+raw[4:8]+data)
run('café-地図.sav',raw)
run('bad-header.sav',b'not a save',False)
run('truncated-zlib.sav',raw[:-25],False)
run('unsupported-zstd.sav',b'OTTS'+raw[4:8]+b'unsupported',False)
run('corrupt-chunk.sav',b'OTTZ'+raw[4:8]+zlib.compress(data[:-8]),False)
run('invalid-dimensions.sav',b'OTTN'+raw[4:8]+b'MAPS'+bytes([0])+bytes([0,0,8])+struct.pack('>II',123,1024)+bytes(4),False)
print('All save-reader cases passed.')
