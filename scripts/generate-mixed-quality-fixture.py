#!/usr/bin/env python3
"""Freeze author-reviewed examples, without querying any engine or ranking output.
Sources establish lexical provenance; all sentence frames below are authored adaptations.
"""
import gzip, hashlib, itertools, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
# Japanese surface; input; Chinese prefix/suffix pairs. Empty field = no prefix/suffix.
# Chinese slash annotations are plain untoned pinyin, manually reviewed.
SEEDS = r'''
ありがとう;arigatou;今天也/jintianye;;;这次真的帮大忙了/zhecizhendebangdamangle
すごい;sugoi;这个也太/zhegeyetai;了吧/leba;;这关居然一次就过了/zheguanjuranyicijiuguole
こんにちは;konnichiha;进门先说/jinmenxianshuo;;;说完就可以开始上课了/shuowanjiukeyikaishishangkele
おはよう;ohayou;早上记得说/zaoshangjideshuo;;;今天起得真早/jintianqidezhenzao
こんばんは;konbanha;晚上见面说/wanshangjianmianshuo;;;外面已经天黑了/waimianyijingtianheile
おやすみ;oyasumi;睡前说一句/shuiqianshuoyiju;;;明天还要早起/mingtianhaiyaozaoqi
お疲れ様です;otsukaresamadesu;今天辛苦了/jintianxinkule;;;终于下班了/zhongyuxiabanle
よろしくお願いします;yoroshikuonegaishimasu;今后还请多关照/jinhouhaiqingduoguanzhao;;;这个项目拜托了/zhegexiangmubaituole
いただきます;itadakimasu;吃饭前先说/chifanqianxianshuo;;;今天的饭看起来真香/jintiandefankanqilaizhenxiang
ごちそうさま;gochisousama;吃完别忘了说/chiwanbiewangleshuo;;;这顿饭我很满意/zhedunfanwohenmanyi
すみません;sumimasen;借过先说一声/jieguoxianshuoyisheng;;;请问车站怎么走/qingwenchezhanzenmezou
大丈夫;daijoubu;医生说/ yishengshuo;就放心了/jiufangxinle;;我还能继续走/wohainengjixuzou
かわいい;kawaii;这只猫好/zhezhimaohao;;;我想把它带回家/woxiangbatadaihuijia
懐かしい;natsukashii;听到这首歌就觉得/tingdaozheshougejiujuede;;;原来这家店还在/yuanlaizhejiadianhaizai
おいしい;oishii;这碗汤真/zhewantangzhen;;;再给我来一份/zaigeiwolaiyifen
うれしい;ureshii;收到礼物好/shoudaoliwuhao;;;终于收到录取通知了/zhongyushoudaoluqutongzhile
楽しい;tanoshii;今天的活动很/jintiandehuodonghen;;;下次还想一起来/xiacih aixiangyiqilai
難しい;muzukashii;这道题有点/zhedaotiyoudian;;;得再看一遍教程/deizaikanyibianjiaocheng
やばい;yabai;这个价格有点/zhegejiageyoudian;;;钱包快撑不住了/qianbaokuaichengbuzhule
なるほど;naruhodo;听你解释完才懂/tingnijieshiwancaidong;;;原来是这样设置的/yuanlaishizheyangshezhide
コンビニ;konbini;楼下的/louxiade;还开着/haikaizhe;;就在车站旁边/jiuzaichezhanpangbian
ラーメン;ra-men;今天午饭吃/jintianwufanchi;;;记得加一个鸡蛋/jidejiayigejidan
コーヒー;ko-hi-;早餐来杯/zaocanlaibei;;;放凉以后再喝/fangliangyihouzaihe
カフェ;kafe;附近新开的/fujinxinkaide;值得去看看/zhidequkankan;;周末人会很多/zhoumorenhuihenduo
おにぎり;onigiri;路上买个/lushangmaige;;;放包里就能带走/fangbaolijiunengdaizou
お弁当;obentou;明天带份/mingtiandaifen;;;需要加热一下/xuyaojiareyixia
たこ焼き;takoyaki;路边刚烤好的/lubiangangkaohaode;很香/henxiang;;趁热吃才好吃/chenrechicaihaochi
お好み焼き;okonomiyaki;大阪的/dabande;值得尝试/zhidechangshi;;上面的酱可以少一点/shangmiandejiangk eyishaoyidian
うどん;udon;天冷就想吃/tianlengjiuxiangchi;;;面条比想象中粗/miantiaobixiangxiangzhongcu
そば;soba;夏天想吃冷的/xi atianxiangchil engde;;;汤汁另放一碗/tangzhilingfangyiwan
パン;pan;早上烤了两个/zaoshangkaoleliangge;;;夹点黄油更香/jiadianhuangyougengxiang
ケーキ;ke-ki;生日订一个/shengridingyige;;;吃不完放冰箱/chibuwanfangbingxiang
アイス;aisu;天气热想吃/tianqirexiangchi;;;快融化了赶紧吃/kuaironghualeganjinchi
チョコ;choko;给你带了/geinidaile;;;记得分给同事/jidefengeitongshi
スーパー;su-pa-;晚上去/wanshangqu;买点菜/maidiancai;;打折的时候人很多/dazhedeshihourenhenduo
デパート;depa-to;车站旁边的/chezhanpangbiande;今天休息/jintianxiuxi;;顶楼有个小花园/dinglouyougexiaohuayuan
レストラン;resutoran;这家/zhejia;需要预约/xuyaoyuyue;;周末基本没空位/zhoumojibenmeikongwei
ホテル;hoteru;已经订好/yijingdinghao;了/le;;离车站只有五分钟/lichezhanzhiyouwufenzhong
チェックイン;chekkuin;到了先办/daolexianban;;;记得带好护照/jidedaihaohuzhao
チェックアウト;chekkuauto;明早几点/mingzaojidian;;;之后行李可以寄存/zhihouxinglikeyijicun
エレベーター;erebe-ta-;左边的/zuobiande;坏了/huaile;;一次只能坐六个人/yicizhinengzuoliugeren
タクシー;takushi-;下雨了叫辆/xiayulejiaoliang;;;已经到门口了/yijingdaomenkoule
バス;basu;错过最后一班/cuoguozuihouyiban;;;还要等十分钟/h aiyaodengshifenzhong
ホーム;ho-mu;请在三号/qingzaisanhao;等车/dengche;;上的人有点多/shangderen youdianduo
チケット;chiketto;周末演出的/zhoumoyanchude;买到了/maidaole;;已经全部卖完了/yijingquanbumaiwanle
パスポート;pasupo-to;出门确认/chumenqueren;带好了/daihaole;;一定放在安全的地方/yidingfangzaianquandedifang
スマホ;sumaho;刚买的/gangmaide;没电了/meidianle;;放桌上忘拿了/fangzhuoshangwangnale
アプリ;apuri;这个/zhege;更新之后更好用了/gengxinzhihougenghaoyongle;;卸载之后还能恢复数据/xiezaizhihouhainenghuifushuju
パソコン;pasokon;公司的/gongside;今天特别慢/jintiantebieman;;重启之后就正常了/chongqizhihoujiuzhengchangle
キーボード;ki-bo-do;新的/xinde;手感很好/shouganhenhao;;可以切换三种语言/keyiqiehuansanzhongyuyan
マウス;mausu;这个/zhege;连接不上电脑/lianjiebushangdiannao;;换个电池试试看/huangedianchishishikan
ファイル;fairu;刚发的/gangfade;请查收/qingchashou;;下载完记得备份/xiazaiwanjidebeifen
フォルダ;foruda;桌面的/zhuomiande;已经整理好了/yijingzhenglihaole;;名字改成日期就好/mingzigaichengriqijiuhao
メール;me-ru;客户的/kehude;还没回/haimeihui;;附件需要重新发/fujianxuyaochongxinfa
チャット;chatto;先开个/xiankaige;讨论一下/taolunyixia;;记录可以导出吗/jilukeyidaochuma
コメント;komento;下面的/xiamiande;说得很有道理/shuodehenyoudaoli;;请不要发重复内容/qingbuyaofachongfuneirong
スタンプ;sutanpu;这个/zhege;表情太可爱了/biaoqingtaikeaile;;发一个就能表达心情/fayigejiunengbiaodaxinqing
フォロー;foro-;喜欢的话可以/xihuandehuak eyi;;;之后就能看到更新/zhihoujiunengkandaogengxin
ブロック;burokku;不想收到消息就/buxiangshoudaoxiaoxijiu;;;之后还能取消吗/zhihouhainengquxiaoma
ハッシュタグ;hasshutagu;这条内容加上/zhetiaoneirongjiashang;;;可以帮助找到同类内容/keyibangzhuzhaodaotongleineirong
サブスク;sabusuku;这个月取消/zhegeyuequxiao;;;到期以后不会再扣钱/daoqiyihoubuhuizaikouqian
アップデート;appude-to;今晚进行/jinwanjinxing;;;之后记得重启机器/zhihoujidechongqijiqi
ダウンロード;daunro-do;正在/zhengzai;请稍等/qingshaodeng;;完成以后检查文件/wan chengyihoujianchawenjian
ログイン;roguin;换手机需要重新/huanshoujixuyaochongxin;;;失败就重置密码/shibaijiuchongzhimima
パスワード;pasuwa-do;忘记/wangji;也能找回账号/yenengzhaohuizhanghao;;不要告诉别人/buyaogaosubieren
バックアップ;bakkuappu;升级之前先做/shengjizhiqianxianzuo;;;有了就不怕数据丢失/youlejiubupashujud iushi
ライブ;raibu;今晚的/jinwande;非常期待/feichangqidai;;结束后一起吃夜宵/jieshuhouyiqichiyexiao
アニメ;anime;最近在看/zuijinzaikan;;;这一季终于完结了/zheyijizhongyuwanjiele
ゲーム;ge-mu;朋友推荐的/pengyoutuijiande;很好玩/henhaowan;;玩久了记得休息/wanjiulejidexiuxi
ガチャ;gacha;今天不抽/jintianbuchou;了/le;;次数太多钱包受不了/cishutaiduoqianbaoshoubuliao
グッズ;guzzu;会场的/huichangde;已经卖完了/yijingmaiwanle;;网上也能买到/wangshangyenengmaidao
イベント;ibento;周末的/zhoumode;需要报名/xuyaobaoming;;开始前半小时集合/kaishiqianbanxiaoshijihe
カラオケ;karaoke;下班一起去/xiabanyiqiqu;;;唱到一半突然停电了/changdaoyibanturantingdianle
リモート;rimo-to;这周开始/zhezhoukaishi;办公/bangong;;也要按时参加会议/y eyaoanshicanjiahuiyi
オンライン;onrain;会议改成/huiyigaicheng;;;报名不需要到现场/baomingbuxuyaodaoxianchang
オフライン;ofurain;周末参加/zhoumocanjia;活动/huodong;;也能打开保存的文件/yenengdakaibaocundewenjian
スケジュール;sukeju-ru;明天的/mingtiande;发给我看看/fageiwokankan;;排满了就别再加任务/paimanlejiubiezaijiarenwu
プレゼント;purezento;给朋友准备/geipengyouzhunbei;;;包装拆开才知道是什么/baozhuangchaikaicaizhidaoshishenme
お土産;omiyage;旅行回来带了/lvxinghuilaidaile;;;给大家分一下/geidajiafenyixia
ゆっくり;yukkuri;周末就/zhoumojiu;休息吧/xiuxiba;;不用着急慢慢来/buyongzhaojimanmanlai
'''

# Orthographic alternatives are fixed before any ranking run.
ALTERNATIVES={
 'かわいい':['かわいい','可愛い'], 'おいしい':['おいしい','美味しい'],
 'うれしい':['うれしい','嬉しい'], '楽しい':['楽しい','たのしい'],
 '難しい':['難しい','むずかしい'], '大丈夫':['大丈夫','だいじょうぶ'],
 '懐かしい':['懐かしい','なつかしい'],
 'お疲れ様です':['お疲れ様です','お疲れさまです'],
 'ごちそうさま':['ごちそうさま','ご馳走様'],
 'すみません':['すみません','済みません'],
 'たこ焼き':['たこ焼き','たこ焼'], 'お好み焼き':['お好み焼き','お好み焼'],
 'お土産':['お土産','おみやげ'], 'ありがとう':['ありがとう','有難う'],
}
WEB_SOURCES={'こんにちは':'shoshin-greeting','お疲れ様です':'culture-otsukare',
 'かわいい':'wiki-kawaii','懐かしい':'matcha-nostalgia','コメント':'hikky-sns',
 'ガチャ':'wiki-gacha','スタンプ':'hikky-sns','フォロー':'hikky-sns','ブロック':'hikky-sns','ハッシュタグ':'hikky-sns'}

def cn(spec):
    if not spec:return []
    text,code=spec.split('/')
    return [dict(lang='zh',input=code.replace(' ',''),text=text)]

def jp(text,code):
    return dict(lang='ja',input=code,text=text)

cases=[]

def add(rid,segments,category,sources,provenance,split,core,extra=None):
    choices=[ALTERNATIVES.get(s['text'],[s['text']]) if s['lang']=='ja' else [s['text']] for s in segments]
    row=dict(id=rid,input=''.join(s['input'] for s in segments),expected=[''.join(x) for x in itertools.product(*choices)],category=category,sourceIDs=sources,provenance=provenance,split=split,coreVocabulary=core,segments=segments)
    if extra:row.update(extra)
    assert re.fullmatch(r"[a-z'-]+",row['input']),row
    assert all(s['input'] and s['text'] for s in segments)
    cases.append(row)

# All occurrences of a Japanese core are assigned to one split, including controls.
seeds=[]
for i,line in enumerate(SEEDS.strip().splitlines()):
    text,code,pre1,post1,pre2,post2=line.split(';')
    split='development' if i<20 else 'heldout'
    seeds.append((text,code,split))
    for n,(pre,post) in enumerate([(pre1,post1),(pre2,post2)]):
        seg=cn(pre)+[jp(text,code)]+cn(post)
        category='zh-ja-zh' if pre and post else ('zh-ja' if pre else 'ja-zh')
        sources=['mozc-oss-locked']+([WEB_SOURCES[text]] if text in WEB_SOURCES else [])
        if text=='サブスク':sources=['mozc-manual-locked']
        if text=='よろしくお願いします':sources=['mozc-aux-locked']
        if text=='ガチャ':sources=['wiki-gacha']
        add(f'mix-{i+1:03d}-{n+1}',seg,category,sources,'source_vocabulary_adaptation',split,[text])

# Multiple switches: new semantic contexts; all core terms in each row belong to heldout.
MULTI=r'''
下班去/xiabanqu|コンビニ/konbini|买个/maige|おにぎり/onigiri
先到/xiandao|ホテル/hoteru|再去/ zaiqu|レストラン/resutoran
打开/dakai|アプリ/apuri|就能参加/jiunengcanjia|イベント/ibento
今天的/jintiande|ライブ/raibu|结束后去/jieshuhouqu|カラオケ/karaoke
我的/wode|スマホ/sumaho|找不到/zhaobudao|パスワード/pasuwa-do
请把/qingba|ファイル/fairu|放进/fangjin|フォルダ/foruda
完成/wancheng|アップデート/appude-to|以后再/yihouzai|ログイン/roguin
先做/xianzuo|バックアップ/bakkuappu|再开始/zaikaishi|ダウンロード/daunro-do
新开的/xinkaide|カフェ/kafe|只卖/zhimai|コーヒー/ko-hi-
去/qu|スーパー/su-pa-|买点/maid ian|パン/pan
买了/maile|チケット/chiketto|才能进/c ainengjin|ライブ/raibu
喜欢这个/xihuanzhege|アニメ/anime|所以买了/suoyimaile|グッズ/guzzu
给你/geini|フォロー/foro-|也留了/yeliule|コメント/komento
会议改为/huiyigaiwei|オンライン/onrain|记得检查/jidejiancha|メール/me-ru
打开/dakai|パソコン/pasokon|接上/jieshang|キーボード/ki-bo-do
生日买了/shengrimaile|ケーキ/ke-ki|还准备了/haizhunbeile|プレゼント/purezento
订好/dinghao|ホテル/hoteru|别忘了/biewangle|チェックイン/chekkuin
玩/wan|ゲーム/ge-mu|的时候突然收到/deshihouturanshoudao|メール/me-ru
下楼买/xialoumai|チョコ/choko|和/he|アイス/aisu
发个/fage|スタンプ/sutanpu|再开个/zaikaige|チャット/chatto
'''
for i,line in enumerate(MULTI.strip().splitlines()):
    seg=[]
    for n,part in enumerate(line.split('|')):
        t,c=part.split('/');seg.append(dict(lang='zh' if n%2==0 else 'ja',input=c.replace(' ',''),text=t))
    add(f'multi-{i+1:03d}',seg,'multiple-switches',['mozc-oss-locked'],'source_vocabulary_adaptation','heldout',[s['text'] for s in seg if s['lang']=='ja'])

# Pure-language controls are not counted as mixed expressions.
for i,(text,code,split) in enumerate(seeds[20:50]):
    add(f'ja-control-{i+1:03d}',[jp(text,code)],'pure-ja',['mozc-oss-locked'],'source_vocabulary_adaptation',split,[text])
CN=r'''
你好/nihao
今天也谢谢你/jintianyexiexieni
这次真的帮大忙了/zhecizhendebangdamangle
明天早上见/mingtianzaoshangjian
周末一起吃饭/zhoumoyiqichifan
请问车站怎么走/qingwenchezhanzenmezou
附近有没有便利店/fujinyoumeiyoubianlidian
手机忘在家里了/shoujiwangzaijialile
这个应用很好用/zhegeyingyonghenhaoyong
键盘输入很丝滑/jianpanshuruhensihua
文件已经发给你了/wenjianyijingfageinile
记得备份数据/jidebeifenshuju
密码不要告诉别人/mimabuyaogaosubieren
更新以后需要重启/gengxinyihouxuyaochongqi
今天晚上有演出/jintianwanshangyouyanchu
门票已经卖完了/menpiaoyijingmaiwanle
下班去超市买菜/xiabanquchaoshimaicai
我的咖啡不要加糖/wodekafeibuyaojiatang
这家餐厅需要预约/zhejiacantingxuyaoyuyue
行李可以寄存吗/xinglikeyijicunma
房间里面没有热水/fangjianlimianmeiyoureshui
错过最后一班车/cuoguozuihouyibanche
外面下雨记得带伞/waimianxiayujidedaisan
明天的会议改成线上/mingtiandehuiyigaichengxianshang
这个项目请多关照/zhegexiangmuqingduoguanzhao
先保存再关闭窗口/xianbaocunzaiguanbichuangkou
网络连接不太稳定/wangluolianjieb utaiwending
已经收到你的消息/yijingshoudaonidexiaoxi
今天就到这里吧/jintianjiudaozheliba
祝你生日快乐/zhunishengrikuaile
'''
for i,line in enumerate(CN.strip().splitlines()):
    add(f'zh-control-{i+1:03d}',cn(line),'pure-zh',['author-authored-control'],'authored_control','development' if i<6 else 'heldout',[])

# Explicit adaptations of verified excerpts: remove punctuation and simplify Chinese only.
# Some excerpts mention Japanese metalinguistically; they are not represented as chat quotes.
EXCERPTS=[
 ('wiki-oshi',[('zh','日语','riyu'),('ja','推し','oshi'),('zh','是一个日语俚语','shiyigeriyuliyu')]),
 ('wiki-kawaii',[('ja','可愛い','kawaii'),('zh','已经成为日本文化的重要要素','yijingchengweiribenwenhuadezhongyaoyaosu')]),
 ('wiki-otaku',[('zh','在日语原文','zairiyuyuanwen'),('ja','おたく','otaku'),('zh','中','zhong')]),
 ('fun-oshi',[('zh','我推','wotui'),('ja','推し','oshi'),('zh','是指自己最支持的对象','shizhizijizuizhichideduixiang')]),
 ('hikky-sns',[('zh','或是令人烦恼的已读不回','huoshilingrenfannaodeyidubuhui'),('ja','既読スルー','kidokusuru-')]),
 ('culture-otsukare',[('zh','也可以直接打','yekeyizhijieda'),('ja','お疲れ様です','otsukaresamadesu'),('zh','超实用','chaoshiyong')]),
 ('matcha-nostalgia',[('zh','就会充分感受到浓浓的','jiuhuichongfenganshoudaonongnongde'),('ja','懐かしい','natsukashii'),('zh','氛围','fenwei')]),
 ('shoshin-greeting',[('zh','不要每次都是','buyaomeicidoushi'),('ja','こんにちは','konnichiha')]),
]
devcore={t for t,c,s in seeds if s=='development'}
for i,(source,parts) in enumerate(EXCERPTS):
    core=[t for lang,t,c in parts if lang=='ja']
    # kawaii written 可愛い shares its lexical family with development かわいい.
    split='development' if any(t in devcore or t=='可愛い' for t in core) else 'heldout'
    add(f'source-{i+1:03d}',[dict(lang=l,text=t,input=c) for l,t,c in parts],'source-excerpt-adaptation',[source],'source_excerpt_adaptation',split,core,dict(adaptations=['punctuation removed','Chinese simplified','roman input authored','wiki-oshi initial definition label expanded'] if source=='wiki-oshi' else ['punctuation removed','Chinese simplified','roman input authored']))

# A few declared development-only ambiguity/typo probes, outside the clean-input metric.
add('dev-typo-001',[dict(lang='zh',input='jintianye',text='今天也'),jp('ありがとう','arigadou')],'development-typo',['user-brief'],'development','development',['ありがとう'],dict(excludeFromCleanAccuracy=True))
add('dev-ambiguous-001',[dict(lang='zh',input='kan',text='看'),jp('すごい','sugoi')],'development-boundary',['author-authored-control'],'development','development',['すごい'])

# Lexical source audit: read raw upstream sources only, never engine results.
lookup={}
for path in sorted((ROOT/'Vendor/Lexicons/japanese').glob('dictionary*.txt.gz')):
    with gzip.open(path,'rt') as f:
        for line in f:
            cols=line.rstrip('\n').split('\t')
            if len(cols)>=5:lookup.setdefault(cols[4],(path.name,cols[0]))
manual={}
for path in (ROOT/'Vendor/Lexicons/mozc').glob('*.gz'):
    if path.name not in ['words.gz','places.gz']:continue
    with gzip.open(path,'rt') as f:
        for line in f:
            if not line.startswith('#'):
                cols=line.rstrip('\n').split('\t')
                if len(cols)>=3:manual[cols[1]]=(path.name,cols[0])
for row in cases:
    row['lexicalSourceAudit']=[dict(surface=t,upstreamMatch=(lookup.get(t) or manual.get(t)),scope='surface/reading evidence only; no claim the whole sentence is upstream') for t in row['coreVocabulary']]
ids=[r['id'] for r in cases]
assert len(ids)==len(set(ids))
primary=[r['expected'][0] for r in cases if not r.get('excludeFromCleanAccuracy')]
assert len(primary)==len(set(primary)), 'duplicate target expression'
assert len(cases)>=200
assert sum(len({s['lang'] for s in r['segments']})==2 for r in cases)>=100
meta=dict(schemaVersion=1,fixtureRevision=2,status='Frozen before engine evaluation; no ranking output consulted.',authorship='Sentence adaptations written for QA; only source excerpts have verified verbatim origins.',romaji='Hepburn-style ASCII IME input; particles は/へ use ha/he; long-vowel mark uses hyphen; Chinese uses untoned full pinyin.',splitPolicy='Japanese lexical family disjoint: first20seed families development; remaining seed families heldout. Source aliases 可愛い/かわいい share development. Do not tune against heldout.',sources={
'mozc-oss-locked':dict(url='https://github.com/google/mozc/tree/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/dictionary_oss',license='Mixed; see upstream LICENSE and README.txt'),
'mozc-manual-locked':dict(url='https://github.com/google/mozc/tree/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/dictionary_manual',license='See upstream root LICENSE dictionary* notices'),
'mozc-aux-locked':dict(url='https://github.com/google/mozc/blob/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/dictionary_oss/aux_dictionary.tsv',license='See upstream root LICENSE dictionary* notices'),
'wiki-gacha':dict(url='https://ja.wikipedia.org/wiki/ガチャ',retrieved_at='2026-09-26',license='CC-BY-SA-4.0',scope='Vocabulary reference only; no article sentence copied'),
'web-excerpts':dict(path='Tests/Fixtures/mixed-source-excerpts.json'),
'author-authored-control':dict(description='Original QA text, not a sourced quotation'),
'user-brief':dict(description='User-requested representative development expression/typo')},cases=cases)
for src in json.loads((ROOT/'Tests/Fixtures/mixed-source-excerpts.json').read_text())['entries']:
    meta['sources'][src['id']]={k:src[k] for k in ['url','author','license','license_url','retrieved_at']}
output=ROOT/'Tests/MixedEngineCases.json'
output.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
from collections import Counter
print('Cases:',len(cases),'categories:',dict(Counter(r['category'] for r in cases)),'splits:',dict(Counter(r['split'] for r in cases)))
print('SHA256',hashlib.sha256(output.read_bytes()).hexdigest())
print('Unmatched lexical forms (not failures):',sorted({a['surface'] for r in cases for a in r['lexicalSourceAudit'] if not a['upstreamMatch']}))
