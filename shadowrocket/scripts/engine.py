#!/usr/bin/env python3
"""Generate a reviewed Shadowrocket module; no device telemetry."""
import argparse,collections,datetime,json,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[1]
PROTECT=('apple.com','icloud.com','icloud.com.cn','mzstatic.com','itunes.com','alipay.com','alipayobjects.com','wechat.com','weixin.qq.com','tenpay.com','paypal.com')
VALID=re.compile(r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$')
def domain(s):
 s=str(s or '').strip().lower().rstrip('.')
 return s if VALID.fullmatch(s) else None
def protected(d): return any(d==p or d.endswith('.'+p) for p in PROTECT)
def read_report(path):
 ds=collections.Counter();n=bad=0
 for line in pathlib.Path(path).read_text(encoding='utf-8').splitlines():
  try: x=json.loads(line)
  except (ValueError,TypeError): bad+=1;continue
  if not isinstance(x,dict) or x.get('type')!='networkActivity': continue
  n+=1;d=domain(x.get('domain'))
  if d:ds[d]+=1
 return ds,n,bad
def rules(allow):
 return ['DOMAIN,'+d+',REJECT' for d in sorted(allow) if not protected(d)]
def render(allow):
 return '\n'.join(['#!name=个人定制｜广告拦截（自动更新）','#!desc=已审核域名；无需HTTPS解密；非实时检测。','#!author=Personal Shadowrocket Automation','','[Rule]']+rules(allow)+[''])
def run(path):
 observed,n,bad=read_report(path)
 approved={domain(s) for s in (ROOT/'data/approved_domains.txt').read_text().splitlines() if s.strip() and not s.startswith('#')}
 enabled=observed.keys() & (approved-{None})
 (ROOT/'dist').mkdir(exist_ok=True);(ROOT/'reports').mkdir(exist_ok=True)
 (ROOT/'dist/personal_ads.sgmodule').write_text(render(enabled),encoding='utf-8')
 summary={'generated_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'network_records':n,'unique_domains':len(observed),'invalid_lines':bad,'rule_count':len(rules(enabled)),'note':'Observed requests are not confirmed blocks.'}
 (ROOT/'reports/summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--input',required=True);run(p.parse_args().input)
