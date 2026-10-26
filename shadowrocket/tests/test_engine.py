import pathlib,sys,tempfile,unittest,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'scripts'))
from engine import domain,protected,read_report,render
class TestEngine(unittest.TestCase):
 def test_domain(self): self.assertEqual(domain('GDT.QQ.COM.'),'gdt.qq.com');self.assertIsNone(domain('a,REJECT'))
 def test_protection(self): self.assertTrue(protected('pay.alipay.com'));self.assertFalse(protected('gdt.qq.com'))
 def test_render(self): self.assertIn('DOMAIN,gdt.qq.com,REJECT',render({'gdt.qq.com','alipay.com'}));self.assertNotIn('DOMAIN,alipay.com,REJECT',render({'gdt.qq.com','alipay.com'}))
 def test_parser(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'x.ndjson';p.write_text(json.dumps({'type':'networkActivity','domain':'gdt.qq.com'})+'\ninvalid\n')
   ds,n,bad=read_report(p);self.assertEqual((ds['gdt.qq.com'],n,bad),(1,1,1))
if __name__=='__main__':unittest.main()
