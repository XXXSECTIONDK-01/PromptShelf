// Executed only after a user starts a Notes operation. No System Events or UI scripting.
ObjC.import('Foundation');
function run(argv) {
    var N = Application('com.apple.Notes');
    function fail(message, code) { var e = new Error(message); e.number = code || 1001; throw e; }
    // Notes' string IDs are not reliably accepted by its unique-ID/exists resolver.
    // Read IDs as values, then address the collection by index and verify it again.
    function lookup(elements, id, message, errorCode) {
        var ids = elements.id();
        if (!Array.isArray(ids)) ids = ids == null ? [] : [ids];
        for (var i = 0; i < ids.length; i++) {
            if (String(ids[i]) !== id) continue;
            var item = elements.at(i);
            if (item.id() !== id) fail('备忘录列表发生变化，请刷新后重试。',1003);
            return item;
        }
        fail(message,errorCode);
    }
    function account(id) { return lookup(N.accounts,id,'备忘录账户不存在，请重新连接。'); }
    // Resolve notes from folder-returned references. Notes' account-wide indexed
    // note collection and freshly returned make specifiers can be stale.
    function note(a, id, folderID) {
        var choices = folders(a).filter(function(f){return !folderID || f.id === folderID;});
        for (var i = 0; i < choices.length; i++) {
            var items = choices[i].ref.notes();
            for (var j = 0; j < items.length; j++) {
                if (items[j].id() === id) return {ref:items[j],id:id,folderID:choices[i].id};
            }
        }
        fail('备忘录已被移除或移动，请刷新后重试。',-1728);
    }
    function waitFor(check, message) {
        for (var attempt = 0; attempt < 50; attempt++) {
            try { var result = check(); if (result) return result; }
            catch(e) { if (Number(e.errorNumber || e.number) !== -1728) throw e; }
            delay(0.2);
        }
        fail(message,1004);
    }
    function folders(a) {
        var all = [], seen = {};
        function walk(container, prefix, depth) {
            if (depth > 20) fail('备忘录文件夹层级过深。');
            container.folders().forEach(function(f) {
                var id = f.id(); if (seen[id]) return; seen[id] = true;
                var name = f.name(), path = prefix ? prefix + ' / ' + name : name;
                all.push({id:id,name:name,path:path,ref:f,root:depth === 0});
                if (all.length > 1000) fail('文件夹超过 1000 个，请精简后重试。');
                walk(f,path,depth+1);
            });
        }
        walk(a,'',0); return all;
    }
    function iso(d) { return d ? new Date(d).toISOString() : ''; }
    function isMD(name) { return /\.(md|markdown)$/i.test(name); }
    function safeName(name) { return name && name.length <= 240 && !/[\/\\:\x00-\x1f\x7f]/.test(name) && isMD(name); }
    function markdownAttachments(n) {
        return n.attachments().filter(function(a){return isMD(a.name());});
    }
    function attachments(n) {
        // Link previews, scans and other non-file objects may not expose dates.
        // Their changes are covered by the note date; never inspect their metadata.
        return markdownAttachments(n).map(function(a){return {id:a.id(),name:a.name()};});
    }
    function revision(context) {
        var n = context.ref;
        return JSON.stringify([context.id,context.folderID,iso(n.modificationDate()),attachments(n)]);
    }
    function locked(n) { return Boolean(n.passwordProtected()); }
    var request, createdID = null, stagingCreated = false, exportAccount = null, stage = '读取同步请求';
    try {
        if (argv.length !== 1) fail('同步请求无效。');
        var raw = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
        if (!raw) fail('无法读取同步请求。');
        request = JSON.parse(ObjC.unwrap(raw));
        var result;
        if (request.action === 'accounts') {
            stage = '读取备忘录账户';
            result = N.accounts().map(function(a) { return {id:a.id(),name:a.name()}; });
        } else if (request.action === 'folders') {
            stage = '读取备忘录文件夹';
            result = folders(account(request.accountID)).map(function(f){return {id:f.id,name:f.name,path:f.path};});
        } else if (request.action === 'list') {
            stage = '读取笔记列表';
            var acc = account(request.accountID), matches = folders(acc).filter(function(f){return f.id === request.folderID;});
            if (!matches.length) fail('文件夹不存在或不属于所选账户，请刷新后重试。');
            var folder = matches[0].ref;
            var items = folder.notes(), start = Math.max(0, request.offset || 0), limit = Math.min(100, request.limit || 100);
            result = {total:items.length, entries:items.slice(start,start+limit).map(function(n) {
                var protect = locked(n), count = protect ? 0 : n.attachments.name().filter(isMD).length;
                return {id:n.id(),name:n.name(),modified:iso(n.modificationDate()),locked:protect,markdownCount:count};
            })};
        } else if (request.action === 'read') {
            stage = '读取笔记正文';
            var acc = account(request.accountID), context = note(acc,request.noteID,request.folderID), n = context.ref;
            if (locked(n)) fail('此备忘录已锁定。请先在备忘录中解锁，再重新同步。',1002);
            var before = revision(context), docs = markdownAttachments(n);
            if (docs.length > 20) fail('单条备忘录最多支持 20 个 Markdown 附件。');
            var title = n.name(), text = n.plaintext();
            if (text.length > 1000000) fail('备忘录正文超过导入上限。');
            var files = docs.map(function(a,index) {
                var name = a.name();
                if (!safeName(name)) fail('Markdown 附件文件名无效。');
                stage = '读取 Markdown 附件';
                var path = request.directory + '/' + index + '.md';
                N.save(a,{in:Path(path)});
                return {name:name,path:path};
            });
            var after = revision(note(acc,request.noteID,context.folderID));
            if (after !== before) fail('读取期间备忘录发生变化，请重试。',1003);
            result = {id:n.id(),title:title,plainText:text,revision:after,files:files,folderID:context.folderID};
        } else if (request.action === 'revision') {
            stage = '检查笔记版本';
            var context = note(account(request.accountID),request.noteID,request.folderID);
            if (locked(context.ref)) fail('此备忘录已锁定。',1002);
            result = revision(context);
        } else if (request.action === 'export') {
            stage = '保存提示词到备忘录';
            var acc = account(request.accountID), files = request.files || [];
            if (files.length > 20) fail('附件数量超过上限。');
            files.forEach(function(f) {
                if (!safeName(f.name) || !$.NSFileManager.defaultManager.fileExistsAtPath(f.path)) fail('Markdown 附件不可用。');
            });
            exportAccount = acc;
            var targets = folders(acc).filter(function(f){return f.name === '词屿' && f.root;});
            if (!targets.length) {
                stage = '创建词屿文件夹';
                N.make({new:'folder',at:acc,withProperties:{name:'词屿'}});
                targets = [waitFor(function(){
                    return folders(acc).filter(function(f){return f.name === '词屿' && f.root;})[0];
                },'文件夹尚未就绪，请稍后重试。')];
            }
            var destination = targets[0], folderID = destination.id;
            // A unique staging title lets us rediscover OUR note from Notes' own
            // collection, rather than trusting make's temporary object reference.
            var token = '词屿同步 · ' + (request.operationID || ObjC.unwrap($.NSUUID.UUID.UUIDString));
            stage = '创建备忘录笔记';
            N.make({new:'note',at:destination.ref,withProperties:{body:'<h1>' + token + '</h1>'}});
            stagingCreated = true;
            var context = waitFor(function(){
                var items = destination.ref.notes();
                for (var i = 0; i < items.length; i++) {
                    if (items[i].name() === token) return {ref:items[i],id:items[i].id(),folderID:folderID};
                }
                return null;
            },'新建笔记尚未就绪，请稍后重试。');
            createdID = context.id;
            stage = '保存笔记正文';
            context.ref.body = request.html;
            context = waitFor(function(){
                var fresh = note(acc,createdID,folderID);
                return fresh.ref.name() === request.title ? fresh : null;
            },'笔记正文尚未写入，请稍后重试。');
            if (files.length) {
                stage = '保存 Markdown 附件';
                files.forEach(function(f){
                    var fresh = note(acc,createdID,folderID);
                    N.make({new:'attachment',at:fresh.ref,withData:Path(f.path)});
                });
                var expected = files.map(function(f){return f.name;}).sort();
                context = waitFor(function(){
                    var fresh = note(acc,createdID,folderID);
                    var saved = attachments(fresh.ref).map(function(f){return f.name;}).sort();
                    return JSON.stringify(saved) === JSON.stringify(expected) ? fresh : null;
                },'Markdown 附件尚未完整写入，请稍后重试。');
            }
            stage = '核对已保存笔记';
            var verified = waitFor(function(){
                var fresh = note(acc,createdID,folderID);
                return {id:fresh.id,revision:revision(fresh)};
            },'笔记尚未完成本地保存，请稍后重试。');
            result = {noteID:verified.id,revision:verified.revision,folderID:folderID};
            createdID = null; stagingCreated = false;
        } else fail('不支持的同步操作。');
        return JSON.stringify({ok:true,result:result});
    } catch(e) {
        var cleanup = '';
        if (createdID !== null) {
            try { N.delete(note(exportAccount,createdID).ref); }
            catch(ignore) { cleanup = ' 新建笔记可能已保留，请在「词屿」文件夹中检查后重试。'; }
        } else if (stagingCreated) { cleanup = ' 请检查「词屿」文件夹中是否留有「词屿同步」临时笔记。'; }
        var errorCode = Number(e.errorNumber || e.number || 1000);
        return JSON.stringify({ok:false,error:{code:errorCode,message:stage + '失败（' + errorCode + '）：' + String(e.message || e) + cleanup}});
    }
}
