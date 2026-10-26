import json, sys, urllib.request, time
WANT={'ES2004a','IS1009a','TS3003a','EN2002a'}
rows=[]; off=0
while True:
    url=f"https://datasets-server.huggingface.co/rows?dataset=edinburghcstr/ami&config=sdm&split=test&offset={off}&length=100"
    for attempt in range(5):
        try:
            d=json.load(urllib.request.urlopen(url, timeout=60)); break
        except Exception as e:
            time.sleep(2+attempt*2)
    else: raise SystemExit(f"échec à offset {off}")
    for r in d['rows']:
        r=r['row']
        if r['meeting_id'] in WANT:
            rows.append({'session_id':r['meeting_id'],'speaker':r['speaker_id'],'start_time':round(r['begin_time'],3),'end_time':round(r['end_time'],3),'words':r['text']})
    off+=100
    if off>=d['num_rows_total']: break
json.dump(rows, open('ami_ref.seglst.json','w'))
from collections import Counter
print(len(rows), Counter(r['session_id'] for r in rows))
