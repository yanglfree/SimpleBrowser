import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { repositoryRoot } from './reader-core-source.mjs';
import { loadEts } from './ets-module.mjs';

function environment() {
  const files = new Map();
  const tables = new Map();
  let checkpoint;
  let failCommit = false;
  let failWrite = false;
  class Predicates {
    constructor(table) { this.table=table;this.filters=[]; }
    equalTo(key,value){this.filters.push([key,value]);return this;}
    orderByDesc(){return this;}
    orderByAsc(){return this;}
  }
  const result = rows => {
    let position=-1;
    return {goToFirstRow:()=>{position=0;return rows.length>0;},goToNextRow:()=>++position<rows.length,
      getColumnIndex:name=>name,getString:key=>String(rows[position][key]??''),
      getLong:key=>Number(rows[position][key]??0),close(){}};
  };
  const store = {
    executeSql:async()=>{},querySql:async()=>result([]),
    query:async predicates=>result([...tables.get(predicates.table)?.values()??[]].filter(row=>
      predicates.filters.every(([key,value])=>row[key]===value))),
    beginTransaction(){checkpoint=new Map([...tables].map(([key,value])=>[key,new Map(value)]));},
    commit(){if(failCommit)throw new Error('Injected database failure');},
    rollBack(){tables.clear();for(const [key,value] of checkpoint)tables.set(key,value);},
    insertSync(table,row){
      if(!tables.has(table))tables.set(table,new Map());
      tables.get(table).set(row.id??row.article_id,{...row});return 1;
    },
    async insert(...args){return this.insertSync(...args);},
    deleteSync(predicates){for(const [id,row] of tables.get(predicates.table)??[]) {
      if(predicates.filters.every(([key,value])=>row[key]===value))tables.get(predicates.table).delete(id);
    }},
    async delete(predicates){this.deleteSync(predicates);},
    async update(values,predicates){for(const row of tables.get(predicates.table)?.values()??[])
      if(predicates.filters.every(([key,value])=>row[key]===value))Object.assign(row,values);}
  };
  const fileIo = {
    OpenMode:{READ_WRITE:1,CREATE:2,TRUNC:4},
    access:async p=>files.has(p)||[...files.keys()].some(key=>key.startsWith(p+'/')),
    mkdir:async p=>files.set(p,null),
    open:async p=>({fd:p}),close:async()=>{},
    write:async(p,value)=>{if(failWrite)throw new Error('Injected disk failure');files.set(p,value);},
    readText:async p=>{if(!files.has(p))throw new Error('Missing content');return files.get(p);},
    rmdir:async p=>{for(const key of files.keys())if(key===p||key.startsWith(p+'/'))files.delete(key);}
  };
  const repoType = loadEts('entry/src/main/ets/repositories/ArticleLibraryRepository.ets', {
    '@kit.AbilityKit':{},'@kit.CoreFileKit':{fileIo},
    '@ohos.data.relationalStore':{getRdbStore:async()=>store,SecurityLevel:{S1:1},RdbPredicates:Predicates,
      ConflictResolution:{ON_CONFLICT_REPLACE:1}},
    '../services/ArticleImageStore':{ArticleImageStore:{persist:async images=>({savedCount:images.length,failedCount:0})}}
  }).ArticleLibraryRepository;
  const vmPath='entry/src/main/ets/viewmodels/BrowserViewModel.ets';
  const adapters=Object.fromEntries([...fs.readFileSync(path.join(repositoryRoot,vmPath),'utf8')
    .matchAll(/from '([^']+)'/g)].map(match=>[match[1],{}]));
  adapters['../models/ArticleLibraryModels']=loadEts('entry/src/main/ets/models/ArticleLibraryModels.ets');
  adapters['../utils/UrlUtils']={displayHost:url=>new URL(url).hostname};
  const ViewModel=loadEts(vmPath,adapters).BrowserViewModel;
  const viewModel=Object.create(ViewModel.prototype);
  viewModel.articleLibrary=new repoType();
  return {viewModel,files,tables,failCommit:value=>{failCommit=value;},failWrite:value=>{failWrite=value;}};
}

async function save(vm,text='Original content',quality='complete') {
  return vm.saveExtractedArticle('https://example.test/article','https://example.test/article',
    'Title','Author',text,text?`<article>${text}</article>`:'',text,[],quality);
}

test('empty extraction is a failure result, never a successful save',async()=>{
  const env=environment();await env.viewModel.articleLibrary.initialize({filesDir:'/test-files'});
  const result=await save(env.viewModel,'','unavailable');
  assert.equal(result.failure,1);assert.equal(result.preserved,false);
  assert.equal((await env.viewModel.listSavedArticles())[0].failure,1);
});

test('failed recapture and database failure preserve the prior committed content',async()=>{
  const env=environment();const vm=env.viewModel;await vm.articleLibrary.initialize({filesDir:'/test-files'});
  const initial=await save(vm);
  assert.equal(initial.failure,0);
  const oldContent=await vm.articleLibrary.getArticleContent(initial.articleId);
  const empty=await save(vm,'','unavailable');assert.equal(empty.preserved,true);
  env.failCommit(true);
  const failed=await save(vm,'New content');assert.equal(failed.failure,2);assert.equal(failed.preserved,true);
  const current=await vm.articleLibrary.getArticleContent(initial.articleId);
  assert.equal(current.htmlPath,oldContent.htmlPath);
  assert.equal(await vm.readSavedArticleMarkdown(initial.articleId),'Original content');
  assert.equal((await vm.listSavedArticles())[0].failure,0);
});

test('disk failure preserves the old version and a later retry succeeds without duplication',async()=>{
  const env=environment();const vm=env.viewModel;await vm.articleLibrary.initialize({filesDir:'/test-files'});
  const initial=await save(vm);
  env.failWrite(true);assert.equal((await save(vm,'Replacement')).failure,2);
  assert.equal(await vm.readSavedArticleMarkdown(initial.articleId),'Original content');
  env.failWrite(false);assert.equal((await save(vm,'Replacement')).failure,0);
  assert.equal((await vm.listSavedArticles()).length,1);
  assert.equal(await vm.readSavedArticleMarkdown(initial.articleId),'Replacement');
});

test('annotation editing, removal and article deletion are scoped to the selected article',async()=>{
  const env=environment();const vm=env.viewModel;await vm.articleLibrary.initialize({filesDir:'/test-files'});
  const {articleId}=await save(vm);
  const note=await vm.articleLibrary.createNote(articleId,'Old note');
  await vm.articleLibrary.updateNote(articleId,note.id,'Edited note');
  assert.equal((await vm.articleLibrary.listNotes(articleId))[0].body,'Edited note');
  await vm.articleLibrary.deleteAnnotation('different-article',note.id,false);
  assert.equal((await vm.articleLibrary.listNotes(articleId)).length,1);
  await vm.articleLibrary.deleteArticle(articleId);
  assert.equal((await vm.listSavedArticles()).length,0);
  assert.equal((await vm.articleLibrary.listNotes(articleId)).length,0);
  assert.equal([...env.files.keys()].some(p=>p.includes(articleId)),false);
});

test('concurrent save and capture failure never replace a committed readable article',async()=>{
  const env=environment();const vm=env.viewModel;await vm.articleLibrary.initialize({filesDir:'/test-files'});
  const [saved]=await Promise.all([save(vm),vm.saveArticleFailure('https://example.test/article','Title','',4)]);
  assert.equal((await vm.listSavedArticles()).length,1);
  assert.equal((await vm.getSavedArticle(saved.articleId)).failure,0);
  assert.equal(await vm.readSavedArticleMarkdown(saved.articleId),'Original content');
});
