import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Home()));
}
Future<List<dynamic>> readKids() async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(prefs.getString('yt_kids_v1') ?? '[]') as List<dynamic>;
}
Future<void> writeKids(List<dynamic> kids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('yt_kids_v1', jsonEncode(kids));
}
int total(Map<String,dynamic> kid) => (kid['history'] as List).fold<int>(
  0, (sum, item) => sum + (item['delta'] as num).toInt());
String money(int points) => String.fromCharCode(36) + (points * .5).toStringAsFixed(2);
Widget face(Map<String,dynamic> kid, double size) {
  final photo = kid['photo']?.toString() ?? '';
  return CircleAvatar(radius:size/2,backgroundColor:const Color(0xffe5d6ff),
    backgroundImage:photo.isNotEmpty && File(photo).existsSync() ? FileImage(File(photo)) : null,
    child:photo.isNotEmpty && File(photo).existsSync() ? null :
      Text((kid['name'] as String).substring(0,1).toUpperCase(),style:TextStyle(fontSize:size*.42)));
}
Future<String?> ask(BuildContext context,String title,{bool numeric=false}) async {
  final controller=TextEditingController();
  final answer=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(title),
    content:TextField(controller:controller,autofocus:true,
      keyboardType:numeric?const TextInputType.numberWithOptions(decimal:true):TextInputType.text),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('Save'))]));
  controller.dispose();
  return answer;
}
class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> {
  List<dynamic> kids=[];
  @override void initState(){super.initState();reload();}
  Future<void> reload() async {
    final result=await readKids();
    if(mounted)setState(()=>kids=result);
  }
  Future<void> add() async {
    final name=await ask(context,'Child name');
    if(name==null||name.isEmpty)return;
    kids.add({'id':DateTime.now().microsecondsSinceEpoch.toString(),
      'name':name,'photo':'','history':<dynamic>[]});
    await writeKids(kids);await reload();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:Colors.white,
    appBar:AppBar(backgroundColor:const Color(0xfff4edff),
      title:const Text('YT Points',style:TextStyle(color:Color(0xff5823ae),fontWeight:FontWeight.bold))),
    floatingActionButton:FloatingActionButton.extended(onPressed:add,
      icon:const Icon(Icons.person_add),label:const Text('Add Child')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Your Kids',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
      const SizedBox(height:16),
      if(kids.isEmpty)const Text('Add a child to start tracking points.'),
      ...kids.map((item){
        final kid=Map<String,dynamic>.from(item as Map);
        return Card(color:Colors.white,child:ListTile(
          contentPadding:const EdgeInsets.all(16),
          leading:face(kid,56),title:Text(kid['name'].toString()),
          subtitle:Text(total(kid).toString()+' points  |  '+money(total(kid))),
          trailing:const Icon(Icons.chevron_right),
          onTap:()async{
            await Navigator.push(context,MaterialPageRoute(
              builder:(_)=>Profile(id:kid['id'].toString())));
            await reload();
          }));
      }),
    ]));
}
class Profile extends StatefulWidget {
  final String id;
  const Profile({super.key,required this.id});
  @override State<Profile> createState()=>_ProfileState();
}
class _ProfileState extends State<Profile> {
  List<dynamic> kids=[];
  int index=-1;
  Map<String,dynamic> get kid=>Map<String,dynamic>.from(kids[index] as Map);
  @override void initState(){super.initState();reload();}
  Future<void> reload() async {
    final result=await readKids();
    if(mounted)setState((){
      kids=result;
      index=result.indexWhere((item)=>item['id']==widget.id);
    });
  }
  Future<void> save(Map<String,dynamic> updated) async {
    kids[index]=updated;
    await writeKids(kids);
    await reload();
  }
  Future<void> photo() async {
    final choice=await showModalBottomSheet<String>(context:context,
      builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
        ListTile(leading:const Icon(Icons.photo_library),title:const Text('Choose from Gallery'),
          onTap:()=>Navigator.pop(ctx,'gallery')),
        ListTile(leading:const Icon(Icons.camera_alt),title:const Text('Take Photo'),
          onTap:()=>Navigator.pop(ctx,'camera')),
        ListTile(leading:const Icon(Icons.delete),title:const Text('Remove Photo'),
          onTap:()=>Navigator.pop(ctx,'remove')),
      ])));
    if(choice==null)return;
    final updated=kid;
    if(choice=='remove'){updated['photo']='';await save(updated);return;}
    try {
      final picked=await ImagePicker().pickImage(
        source:choice=='camera'?ImageSource.camera:ImageSource.gallery,
        maxWidth:900,maxHeight:900,imageQuality:80);
      if(picked==null)return;
      final dir=await getApplicationDocumentsDirectory();
      final filename='kid_'+DateTime.now().microsecondsSinceEpoch.toString()+
        path.extension(picked.path);
      updated['photo']=(await File(picked.path).copy(path.join(dir.path,filename))).path;
      await save(updated);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Photo error: '+e.toString())));
    }
  }
  Future<void> transact(String kind) async {
    final raw=await ask(context,kind=='purchase'?'Purchase amount in dollars':'Points',numeric:true);
    if(raw==null)return;
    final number=double.tryParse(raw);
    if(number==null||!number.isFinite||number<=0)return;
    final points=kind=='purchase'?(number*2).round():number.round();
    if(points<1||points>1000000||
      (kind=='purchase'?(points/2-number).abs()>0.00001:points!=number)){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Use whole points or purchases in 50-cent increments.')));
      return;
    }
    final delta=kind=='reward'?points:-points;
    if(total(kid)+delta<0){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Insufficient points.')));
      return;
    }
    final reason=await ask(context,'Reason');
    if(reason==null||reason.isEmpty)return;
    final updated=kid;
    (updated['history'] as List).insert(0,{
      'delta':delta,'kind':kind,'reason':reason,
      'date':DateTime.now().toIso8601String().substring(0,10)});
    await save(updated);
  }
  Future<void> rename() async {
    final name=await ask(context,'Child name');
    if(name==null||name.isEmpty)return;
    final updated=kid;updated['name']=name;await save(updated);
  }
  Future<void> remove() async {
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Remove child?'),
      content:const Text('This permanently removes this child and their history from this device.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Remove'))]));
    if(confirmed!=true)return;
    kids.removeAt(index);await writeKids(kids);
    if(mounted)Navigator.pop(context);
  }
  @override Widget build(BuildContext context){
    if(index<0)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final child=kid;
    return Scaffold(backgroundColor:Colors.white,
      appBar:AppBar(backgroundColor:const Color(0xfff4edff),
        title:Text(child['name'].toString()),
        actions:[IconButton(onPressed:rename,icon:const Icon(Icons.edit)),
          IconButton(onPressed:remove,icon:const Icon(Icons.delete_outline))]),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Center(child:InkWell(onTap:photo,child:Stack(children:[
          face(child,112),
          const Positioned(right:0,bottom:0,child:CircleAvatar(
            backgroundColor:Color(0xff6829cc),radius:19,
            child:Icon(Icons.camera_alt,color:Colors.white,size:20))),
        ]))),
        const SizedBox(height:8),
        const Center(child:Text('Tap picture to add or change photo')),
        const SizedBox(height:20),
        Card(color:const Color(0xfff4edff),
          child:Padding(padding:const EdgeInsets.all(24),
            child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[
              Column(children:[Text(total(child).toString(),
                style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold)),const Text('Points')]),
              Column(children:[Text(money(total(child)),
                style:const TextStyle(fontSize:28,color:Colors.green,fontWeight:FontWeight.bold)),
                const Text('Balance')]),
            ]))),
        const SizedBox(height:16),
        Wrap(spacing:8,children:[
          FilledButton(onPressed:()=>transact('reward'),child:const Text('Reward')),
          OutlinedButton(onPressed:()=>transact('deduction'),child:const Text('Deduct')),
          OutlinedButton(onPressed:()=>transact('purchase'),child:const Text('Purchase')),
        ]),
        const SizedBox(height:20),
        const Text('Transaction History',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        ...((child['history'] as List).map((item){
          final entry=Map<String,dynamic>.from(item as Map);
          return Card(child:ListTile(title:Text(entry['reason'].toString()),
            subtitle:Text(entry['kind'].toString()+' • '+entry['date'].toString()),
            trailing:Text(entry['delta'].toString()+' pts')));
        })),
      ]));
  }
}
