#!/usr/bin/env python3
"""Install one checksum-pinned official Godot build into a task-local directory."""
import argparse,hashlib,json,pathlib,subprocess,urllib.request,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def require(v,m):
 if not v:raise RuntimeError(m)
def sha(p,algorithm='sha256'):return hashlib.new(algorithm,pathlib.Path(p).read_bytes()).hexdigest()
def download(url,path):
 require(url.startswith('https://github.com/godotengine/godot-builds/releases/download/'),'Unexpected download origin')
 if not path.exists():
  with urllib.request.urlopen(url,timeout=180) as response:
   require(response.url.startswith('https://'),'Insecure download redirect');path.write_bytes(response.read())
def main():
 p=argparse.ArgumentParser();p.add_argument('--version',choices=['4.3','4.7.2'],required=True);p.add_argument('--tools',type=pathlib.Path,required=True);a=p.parse_args();a.tools=a.tools.resolve();a.tools.mkdir(parents=True,exist_ok=True)
 pin=json.loads((ROOT/'verification/toolchains.json').read_text())['releases'][a.version]
 checksum=a.tools/(a.version+'-SHA512-SUMS.txt');download(pin['officialChecksumUrl'],checksum);require(sha(checksum)==pin['checksumManifestSha256'],'Official checksum manifest differs')
 name=pin['downloadUrl'].split('/')[-1];archive=a.tools/name;download(pin['downloadUrl'],archive)
 rows=[line.split()[0] for line in checksum.read_text().splitlines() if line.split()[-1].lstrip('*')==name]
 require(rows==[pin['officialSha512']],'Official checksum entry differs');require(sha(archive,'sha512')==rows[0],'Archive SHA512 mismatch');require(sha(archive)==pin['archiveSha256'],'Archive SHA256 mismatch')
 dest=a.tools/('godot-'+a.version);dest.mkdir(exist_ok=True)
 with zipfile.ZipFile(archive) as z:
  require(z.namelist()==[name[:-4]],'Unexpected archive inventory');z.extractall(dest)
 binary=dest/name[:-4];require(sha(binary)==pin['binarySha256'],'Extracted engine differs');binary.chmod(0o755)
 report={'status':'verified','version':a.version,'archiveSha256':sha(archive),'officialSha512':sha(archive,'sha512'),'binarySha256':sha(binary),'binaryPath':str(binary),'binaryBytes':binary.stat().st_size,'checksumManifestSha256':sha(checksum),'downloadUrl':pin['downloadUrl'],'officialChecksumUrl':pin['officialChecksumUrl']}
 (a.tools/('godot-'+a.version+'-receipt.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
