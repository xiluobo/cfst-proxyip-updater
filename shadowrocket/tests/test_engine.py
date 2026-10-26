import pathlib,sys,tempfile,unittest,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'scripts'))
from engine import domain,protected,read_report,render,PROTECT
class TestEngine(unittest.TestCase):
 def test_domain(self): self.assertEqual(domain('GDT.QQ.COM.'),'gdt.qq.com');self.assertIsNone(domain('a.REJECT'))
 def test_protection(self): self.assertTrue(protected('pay.alipay.com'));self.assertFalse(protected('gdt.qq.com'))
 def test_render(self): self.assertIn('DOMAIN,gdt.qq.com,REJECT',render({'gdt.qq.com','alipay.com'}));self.assertNotIn('DOMAIN,alipay.com,REJECT',render({'gdt.qq.com','alipay.com'}))
 def test_parser(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'x.ndjson';p.write_text(json.dumps({'type':'networkActivity','domain':'gdt.qq.com'})+'\ninvalid\n')
   ds,n,bad=read_report(p);self.assertEqual((ds['gdt.qq.com'],n,bad),(1,1,1))
 def _generated_domains(self):
  p=pathlib.Path(__file__).resolve().parents[1]/'dist'/'personal_ads.sgmodule';self.assertTrue(p.is_file());return [l.split(',')[1] for l in p.read_text(encoding='utf-8').splitlines() if l.startswith('DOMAIN,') and l.endswith(',REJECT')]
 def test_generated_no_protected(self): self.assertFalse(any(protected(d) for d in self._generated_domains()));self.assertFalse(any(d==p or d.endswith('.'+p) for d in self._generated_domains() for p in PROTECT))
 def test_generated_unique_sorted(self): ds=self._generated_domains();self.assertEqual(ds,sorted(ds));self.assertEqual(len(ds),len(set(ds)))
 def test_generated_valid(self): self.assertTrue(all(domain(d)==d for d in self._generated_domains()))
if __name__=='__main__':unittest.main()
