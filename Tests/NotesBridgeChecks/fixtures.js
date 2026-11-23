var ObjC = {import:function(){},unwrap:function(x){return x;}}, request, state;
var $ = {NSUTF8StringEncoding:4, NSString:{stringWithContentsOfFileEncodingError:function(){return JSON.stringify(request);}}, NSUUID:{UUID:{UUIDString:'offline-operation'}}, NSFileManager:{defaultManager:{fileExistsAtPath:function(){return true;}}}};
function Path(p){return p;}
function delay(){if(state.pending){state.pending.forEach(function(p){p.note._files.push(p.file);});state.pending=[];}}
function heading(html){var m=/<h1>([\s\S]*?)<\/h1>/.exec(html||'');return m?m[1]:html||'';}
function conversionError(){var e=new Error('不能转换类型。');e.number=-1700;throw e;}
function collection(getter){var c=function(){return getter();};c.byId=function(id){if(state.rejectIDLookups)conversionError();return getter().filter(function(x){return x.id()===id;})[0]||{missing:true};};c.id=function(){return getter().map(function(x){return x.id();});};c.at=function(index){return getter()[index];};Object.defineProperty(c,'name',{value:function(){return getter().map(function(x){return x.name();});}});return c;}
function stamp(){return new Date('2026-11-16T00:00:00Z');}
function attachment(id,name){return {id:function(){return id;},name:function(){return name;},modificationDate:stamp};}
function folder(acc,id,name,parent){var f={_notes:[],_folders:[],id:function(){return id;},name:function(){return name;},container:function(){return parent||acc;}};f.notes=collection(function(){return f._notes;});f.folders=collection(function(){return f._folders;});return f;}
function note(f,id,name,text,locked,files){var n={_folder:f,_files:files||[],_name:name,_text:text,_changed:0,id:function(){return id;},name:function(){return n._name;},plaintext:function(){if(locked)throw new Error('Locked plaintext must never be read');return n._text;},passwordProtected:function(){return !!locked;},container:function(){return f;},modificationDate:function(){return new Date(stamp().getTime()+n._changed);}};Object.defineProperty(n,'body',{get:function(){return n._text;},set:function(v){n._text=v;n._name=heading(v);}});n.container.id=f.id;n.attachments=collection(function(){return n._files;});f._notes.push(n);return n;}
function reset(){
 state={accounts:[],writes:{},deleted:[],created:0,failAttach:false,changeOnSave:false};
 var a={_folders:[],id:function(){return 'a';},name:function(){return 'iCloud';}};
 a.folders=collection(function(){return a._folders;});
 a.notes=collection(function(){if(state.rejectAccountNotes){var e=new Error('不能获取对象。');e.errorNumber=-1728;throw e;}function gather(f){return f._notes.concat.apply(f._notes, f._folders.map(gather));}return [].concat.apply([],a._folders.map(gather));});
 state.accounts.push(a);var f=folder(a,'f','Notes');a._folders.push(f);
 state.account=a;state.folder=f;state.original=note(f,'n','标题','标题\n正文',false,[attachment('m','first.md'),attachment('m2','second.markdown'),attachment('p','image.png')]);
}
function stale(){return {id:function(){var e=new Error('不能获取对象。');e.errorNumber=-1728;throw e;},attachments:function(){return [];}};}
function Application(id){
 if(id!=='com.apple.Notes')throw new Error('Unexpected app');
 var app={};app.accounts=collection(function(){if(state.denyNativeError){var e=new Error('Not authorized');e.errorNumber=-1743;throw e;}return state.accounts;});
 app.folders=collection(function(){var all=[];function walk(f){all.push(f);f._folders.forEach(walk);}state.accounts.forEach(function(a){a._folders.forEach(walk);});return all;});
 app.exists=function(x){if(state.rejectIDLookups)conversionError();return x&&!x.missing;};
 app.save=function(a,options){state.writes[options.in]=a.name();if(state.changeOnSave)state.original._changed+=1000;};
 app.make=function(options){
  if(options.new==='folder'){var f=folder(options.at,'managed','词屿');options.at._folders.push(f);return state.staleCreate?stale():f;}
  if(options.new==='note'){state.created++;var n=note(options.at,'new-'+state.created,heading(options.withProperties.body),options.withProperties.body,false,[]);return state.staleCreate?stale():n;}
  if(options.new==='attachment'){if(state.failAttach)throw new Error('Attachment unavailable');var name=options.withData.split('/').pop();var a=attachment('new-att-'+options.at._files.length,name);if(state.delayedAttachments){state.pending=state.pending||[];state.pending.push({note:options.at,file:a});}else if(!state.suppressAttachment){options.at._files.push(a);}return state.staleCreate?stale():a;}
  throw new Error('Unexpected make');
 };
 app.delete=function(n){state.deleted.push(n.id());var a=n._folder._notes;a.splice(a.indexOf(n),1);};return app;
}
function execute(r){request=r;return JSON.parse(run(['mock-request.json']));}
function runBridgeChecks(){
 var count=0;function check(value,label){if(!value)throw new Error(label);count++;}
 reset();var r=execute({action:'accounts'});check(r.ok&&r.result[0].name==='iCloud'&&state.created===0,'List accounts without writes');
 var nested=folder(state.account,'sub','Nested',state.folder);state.folder._folders.push(nested);
 r=execute({action:'folders',accountID:'a'});check(r.ok&&r.result[1].path==='Notes / Nested','Nested folder paths');
 note(state.folder,'locked','Locked','secret',true,[]);
 r=execute({action:'list',accountID:'a',folderID:'f',offset:0,limit:100});check(r.ok&&r.result.entries[0].markdownCount===2&&r.result.entries[1].locked,'Locked metadata without plaintext');
 r=execute({action:'read',accountID:'a',noteID:'n',directory:'/stage'});check(r.ok&&r.result.files.length===2&&state.writes['/stage/0.md']==='first.md'&&state.writes['/stage/1.md']==='second.markdown','Import every Markdown attachment only');
 r=execute({action:'read',accountID:'a',noteID:'locked',directory:'/stage'});check(!r.ok&&r.error.code===1002,'Locked note refused');
 r=execute({action:'export',accountID:'a',title:'Export','html':'<h1>Export</h1>',files:[{name:'one.md',path:'/stage/one.md'},{name:'two.md',path:'/stage/two.md'}]});
 check(r.ok&&state.account._folders.length===2&&state.account._folders[1]._notes[0]._files.length===2,'Export folder and all attachments');
 check(state.original._text==='标题\n正文'&&state.deleted.length===0,'Export preserves existing note');
 r=execute({action:'export',accountID:'a',title:'Version 2',html:'<h1>Version 2</h1><pre>body</pre>',files:[]});check(r.ok&&state.account._folders.length===2&&state.account._folders[1]._notes.length===2,'Reuse folder while preserving versions');
 state.failAttach=true;r=execute({action:'export',accountID:'a',title:'Failed',html:'<h1>Failed</h1><pre>body</pre>',files:[{name:'one.md',path:'/stage/one.md'}]});
 check(!r.ok&&state.deleted.length===1&&state.account._folders[1]._notes.length===2,'Failed attachment rolls back new note only');
 reset();state.original._files=[attachment('bad','../secret.md')];r=execute({action:'read',accountID:'a',noteID:'n',directory:'/stage'});
 check(!r.ok&&Object.keys(state.writes).length===0,'Reject attachment path traversal');
 reset();state.changeOnSave=true;r=execute({action:'read',accountID:'a',noteID:'n',directory:'/stage'});check(!r.ok&&r.error.code===1003,'Concurrent remote edits rejected');
 reset();r=execute({action:'revision',accountID:'a',noteID:'missing'});check(!r.ok&&r.error.code===-1728,'Deleted notes reported explicitly');
 reset();state.rejectIDLookups=true;r=execute({action:'folders',accountID:'a'});check(r.ok&&r.result.length===1,'Folder lookup tolerates Notes ID coercion failure');
 r=execute({action:'list',accountID:'a',folderID:'f',offset:0,limit:100});check(r.ok&&r.result.entries.length===1,'List avoids ID coercion failure');
 r=execute({action:'read',accountID:'a',noteID:'n',directory:'/stage'});check(r.ok&&r.result.files.length===2,'Read avoids ID coercion failure');
 reset();state.denyNativeError=true;r=execute({action:'accounts'});check(!r.ok&&r.error.code===-1743&&r.error.message.indexOf('读取备忘录账户')!==-1,'Native errorNumber and failed step retained');
 reset();state.rejectAccountNotes=true;r=execute({action:'read',accountID:'a',folderID:'f',noteID:'n',directory:'/stage'});check(r.ok&&r.result.plainText==='标题\n正文','Read scoped folder despite broken account-wide notes');
 reset();state.original._files.push({name:function(){return 'website.url';},id:function(){throw new Error('Non-Markdown metadata must not be queried');},modificationDate:function(){throw new Error('Unsupported link-preview date');}});r=execute({action:'read',accountID:'a',folderID:'f',noteID:'n',directory:'/stage'});check(r.ok&&r.result.files.length===2,'Non-Markdown link metadata never queried');
 reset();state.staleCreate=true;state.rejectAccountNotes=true;r=execute({action:'export',accountID:'a',title:'Plain',html:'<h1>Plain</h1><pre>text</pre>',files:[]});check(r.ok&&state.account._folders[1]._notes[0]._name==='Plain','Plain export ignores stale make references');
 reset();state.staleCreate=true;state.delayedAttachments=true;r=execute({action:'export',accountID:'a',title:'Delayed',html:'<h1>Delayed</h1>',files:[{name:'one.md',path:'/stage/one.md'}]});check(r.ok&&state.account._folders[1]._notes[0]._files.length===1,'Wait for delayed attachment indexing');
 reset();state.suppressAttachment=true;r=execute({action:'export',accountID:'a',title:'Incomplete',html:'<h1>Incomplete</h1>',files:[{name:'one.md',path:'/stage/one.md'}]});check(!r.ok&&r.error.code===1004&&state.account._folders[1]._notes.length===0&&state.deleted.length===1,'Incomplete attachment times out and rolls back only own note');
 return count+' Notes bridge checks passed without Apple Events.';
}
