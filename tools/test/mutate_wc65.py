# WorkerCosts MAINTENANCE row 65 battery: the l10n-once gate must fail the way the
# defect looks. Each mutation puts one of the three keys back into one translation
# file (the exact shape the row measured) and the gate must exit non-zero naming it;
# a further mutation puts a key back in the <e k= v=> form the gate also has to read.
#
# RUN IT ALONE. It edits a translation file in place and restores it byte for byte.
#
# Usage: py tools/test/mutate_wc65.py
import hashlib, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GATE = os.path.join(ROOT, "tools", "test", "l10n-once.mjs")
EN = os.path.join(ROOT, "translations", "translation_en.xml")
DE = os.path.join(ROOT, "translations", "translation_de.xml")

ANCHOR = '        <text name="wc_rf_pda_page_dashboard" text="Dashboard"/>\n'
MUTATIONS = [
 ("K1-open-manager-back-in-en", EN, ANCHOR, '        <text name="wc_rf_pda_open_manager" text="Open Worker Manager" />\n' + ANCHOR, "translation_en.xml: wc_rf_pda_open_manager"),
 ("K2-rotation-planner-back-in-en", EN, ANCHOR, ANCHOR + '        <text name="sf_pda_btn_rotation_planner" text="Rotation Planner" />\n', "translation_en.xml: sf_pda_btn_rotation_planner"),
 ("K3-field-detail-back-in-de", DE, None, None, "translation_de.xml: sf_pda_btn_field_detail"),
 ("K4-e-form-back-in-en", EN, ANCHOR, ANCHOR + '        <e k="sf_pda_btn_field_detail" v="Field Detail"/>\n', "translation_en.xml: sf_pda_btn_field_detail"),
]

def sha(b): return hashlib.sha256(b).hexdigest()

def gate():
    r = subprocess.run(["node", GATE, ROOT], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout + r.stderr)

rc, out = gate()
if rc != 0:
    print("BASELINE IS NOT GREEN:\n" + out)
    sys.exit(2)
print("baseline green: " + out.strip().encode("ascii", "replace").decode("ascii"))

killed, survived, badedit = [], [], []
for mid, path, old, new, expect in MUTATIONS:
    original = open(path, "rb").read()
    crlf = b"\r\n" in original
    enc = lambda s: (s.replace("\n", "\r\n") if crlf else s).encode("utf-8")
    if old is None:
        # K3: the de file's own dashboard line is the anchor; put the key back after it.
        text = original.decode("utf-8")
        anchor = [l for l in text.splitlines(True) if 'name="wc_rf_pda_page_dashboard"' in l]
        if len(anchor) != 1:
            badedit.append((mid, "anchor matched %dx" % len(anchor))); print("  !! %s: ANCHOR MISMATCH" % mid); continue
        ob = anchor[0].encode("utf-8")
        nb = ob + enc('        <text name="sf_pda_btn_field_detail" text="Felddetails" />\n')
    else:
        ob, nb = enc(old), enc(new)
    if original.count(ob) != 1:
        badedit.append((mid, "anchor matched %dx" % original.count(ob))); print("  !! %s: ANCHOR MISMATCH" % mid); continue
    mutated = original.replace(ob, nb, 1)
    open(path, "wb").write(mutated)
    if open(path, "rb").read() != mutated:
        open(path, "wb").write(original); badedit.append((mid, "edit did not land")); continue
    try:
        rc, out = gate()
    finally:
        open(path, "wb").write(original)
    if sha(open(path, "rb").read()) != sha(original):
        print("  !! %s: RESTORE FAILED, stopping" % mid); sys.exit(3)
    if rc != 0 and expect in out:
        killed.append(mid); print("  KILLED   %s (gate named %s)" % (mid, expect))
    else:
        survived.append(mid); print("  SURVIVED %s (rc %d)\n%s" % (mid, rc, out))

print("\n==== MUTATION RESULT ====")
print("killed   %d" % len(killed))
print("survived %d" % len(survived))
print("bad edit %d" % len(badedit))
print("all files restored byte-identical (hash-checked per mutation)")
sys.exit(1 if (survived or badedit) else 0)
