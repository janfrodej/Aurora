<!--
   Copyright (C) 2021-2024 Jan Frode Jæger (jan.frode.jaeger@ntnu.no), NTNU, Trondheim, Norway

    This file is part of AURORA, a system to store and manage science data.

    AURORA is free software: you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free
    Software Foundation, either version 3 of the License, or (at your option)
    any later version.

    AURORA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with
    AURORA. If not, see <https://www.gnu.org/licenses/>.

    Description: Edit metadata of any given AURORA entity, template handling, checking etc.
-->
<script context="module">
   // unique counter for instances of component
   let counter = 0;
</script> 

<script>     
   import { getConfig } from "./_config.js";
   import { onMount } from "svelte";
   import { hash2SortedArray,hash2SortedSelect,sendStatusMessage } from "./_tools.js";   
   import { call_aurora } from './_aurora';  
   import Status from "./Status.svelte";
   import { PRESETS_DC } from './_sysschema.js';
   import { PRESETS_COMPUTER } from "./_sysschema.js";
   import Icon from './Icon.svelte';

   // component name
   let compname="MetadataEditor";
   // create a random id number of this instance of InputSearchList
   let myrand = counter++;
   // default value to use in input field
   // type of metadata, eg, dataset, group, computer etc.
   export let type="dataset";
   // id to edit or view metadata of, or 0 if create
   export let id=0;
   // parent when creating an entity
   export let parent=0;
   // computer entity when type is dataset
   export let computer=0;
   // path parameter, required when creating dataset
   export let path="";
   // specify if dataset is to be removed after fetching (by the Store-task of automated datasets)
   export let remove=false;
   // define how the data is being fetched when creating a new dataset
   export let acquire="automated";
   acquire=(acquire.toLowerCase() == "manual" ? "MANUAL" : "AUTOMATED");
   // set that we only want to view existing metadata (readonly)
   export let view=false;
   // allow to fill preset values at start from caller (key => value)
   export let presets={};
   // will be set to true when metadata component is finished doing its work and can signal
   // the caller through this property
   export let finished=false;
   // optional callback upon metadata editor finishing its work
   export let finishedHandle;
   // some internal variables
   let operation="";
   let name="";   
   let templ={};
   let md={};
   let template={};
   let metadata={};
   let mergedkeys=[];  // a composite of template and metadata keys that are to be displayed
   let rmkeys={};      // template keys that have been removed in this session are not to be displayed
   let compl={};
   let compliance={};  
   let complrunning=false;
   let showresult=false;  
   let getdata=false;
   let pcounter=0;
   let create=false;
   let created;
   let update=false;
   let updated;
   let rerender=0;

   let CFG={};
   let disabled=false;

   let addkey="";      
   // convert defined presets to a select array
   let presetslist={};
   if (String(type).toLowerCase() == "computer") {
      presetslist=hash2SortedSelect(PRESETS_COMPUTER);  
   } else {
      presetslist=hash2SortedSelect(PRESETS_DC);   
   }  

   onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // update disabled
      disabled = CFG["www.maintenance"]||false;
   });   

   // get template of an entity
   const getTemplate = () => {
      let params={};
      if (type.toLowerCase() == "dataset") {
         // this is a dataset type
         if (id == 0) { params["parent"]=parent; params["computer"]=computer; } // create
         else { params["id"]=id; } // non-create
         templ=call_aurora("getDatasetTemplate",params);
      } else {
         // this is a non-dataset type template fetching
         params["type"]=String(type).toUpperCase();
         if (id ==0) { params["id"]=parent; } // create
         else { params["id"]=id; } // non-create
         templ=call_aurora("getAggregatedTemplate",params);
      }

   }

   // get the metadata of an entity
   const getMetadata = () => {
      // only possible to fetch metadata if id is not 0
      if (id != 0) {
         // we must make the correct type for calling the rest-method
         let mtype=type.substring(0,1).toUpperCase()+type.substring(1).toLowerCase();
         // put together the method name
         let method="get"+mtype+"Metadata";
         // set id param
         let params={}
         params["id"]=id;
         // call aurora and get metadata
         md=call_aurora(method,params);
      }
   }

   // merge template and metadata keys
   const merge = (t,m) => {
      // create a temporary hash to work with the template and the metadata hashes
      let tmp={};           
      if (t != undefined) { t=t.template; template=t; }
      if (m != undefined) { m=m.metadata; metadata=m; }
      if ((t == undefined) && (m == undefined)) { t=template; m=metadata; }
      // add all keys from template
      // if view is false (not ro-mode)
      // if view is true, we skip this part because we only want stored values
      if (!view) {
         for (let key in t) {
            // add key to temp mergedkeys, only if not in rmkeys or if mandatory
            if (((t[key].flags == undefined) && (rmkeys[key] == undefined)) || 
                ((t[key].flags != undefined) && (t[key].flags.includes["MANDATORY"]))) { tmp[key]=1; }
            // update metadata with presets from caller, having precedence on metadata and template defaults 
            // beware of keys where template enforces certain values. Adding presets that are not in accordance with 
            // these will create complaints in the compliance process
            if ((rmkeys[key] == undefined) && (presets[key] != undefined)) {
               // we have a value in presets for this key - add it to metadata
               metadata[key]=presets[key];
            }
            // update metadata with defaults if empty
            // but only do this the first time oår if tagged as mandatory
            if ((metadata != undefined) && (metadata[key] == undefined) && 
               ((t[key].flags != undefined) && (t[key].flags.includes("MANDATORY")))) {
               if ((t[key].flags != undefined) && ((t[key].flags.includes("MULTIPLE")) || (t[key].flags.includes("SINGULAR")))) {
                  if (Array.isArray(t[key].default)) {
                     // add first template default value to metadata key
                     metadata[key]=t[key].default[0];
                  } else {
                     // add entire template default to metadata key
                     metadata[key]=t[key].default;
                  }   
               } else {
                  // template does not enforce any specific default values, so just add all defaults
                  metadata[key]=t[key].default;
               }
            } else if ((rmkeys[key] == undefined) && (metadata != undefined) && (metadata[key] == undefined)) {
               // add null value, so that it is there, but will not be included when saving to
               // REST-server if not set to something else
               metadata[key] = null;
            }
         }
      }
      // add keys from metadata
      for (let key in metadata) {
         // only add key if not already in tmp from template
         if ((rmkeys[key] == undefined) && (tmp[key] == undefined)) {
            tmp[key]=1;
         }
      }           
      // we now have a hash with all the keys - sort them ascending
      let result=hash2SortedArray(tmp,0);    
      // return the result
      mergedkeys=result;            
      getdata=false;
      showresult=true;      

      return "";
   }

   // get template and metadata
   const getData = () => {
      showresult=false;
      getTemplate();      
      getMetadata(); 
      getdata=true;        
   }

   // add a metadatakey to the metadata
   function addMetadataKey (key) {
      showresult=false;
      // if key is not specified to method, use global addkey-value
      if (key == undefined) { key=addkey; addkey=""; }
      if (key != "") {
         // remove from rmkeys if it is there
         if (rmkeys[key] != undefined) { delete rmkeys[key]; }
         // get number of current values/fields on given key             
         let mcount=(Array.isArray(metadata[key]) ? metadata[key].length : (metadata[key] !== undefined ? 1 : 0)); 
         if ((template[key] == undefined) ||
            ((template[key] != undefined) &&
            ((template[key].max == 0) || (template[key].max > mcount)))) {
            // adding extra field/value to metadata
            // if metadata on given key is empty, create an array    
            if (mcount == 0) { metadata[key]=[]; }
            // if we are adding more values and this key is not an array, we change it
            // to an array.
            else if ((mcount == 1) && (!Array.isArray(metadata[key]))) {
               // save current key value
               let v=metadata[key];
               // make key an array
               metadata[key]=[];
               // add saved value
               metadata[key].push(v); 
            }
            // add a new value to the key
            metadata[key].push(null);                    
            // also add key on mergedkeys so it is included in screen
            // output/DOM           
            //if (!mergedkeys.includes(key)) { mergedkeys.push([key,1]); }
            merge(undefined,undefined);
         } else {
            sendStatusMessage ("Template does not allow adding more of key \""+key+"\"...");            
         }
      }   
     showresult=true;
   }

   // remove a metadata key 
   function removeMetadataKey (key,index) {
      showresult=false;
      // attempt to splice array at the correct position
      if (Array.isArray(metadata[key])) {
         metadata[key].splice(index,1);
         if (metadata[key].length == 0) {
            // we have essentially deleted the last element
            delete metadata[key];     
            // also remove it from template
            rmkeys[key]=1;
         }
      } else {
         // this is not an array, so just a single value - remove it
         if (metadata[key] !== undefined) {
            delete metadata[key];         
         }
         // also remove it from template it
         rmkeys[key]=1;
      }   
      // run a merge to force re-rendering
      merge(undefined,undefined);
   }

   // check a metadata's compliance with templates
   const checkCompliance = () => {
      complrunning=true;
      let params={};
      if (type.toLowerCase() == "dataset") {
         // this is a dataset type
         if (id == 0) { params["parent"]=parent; params["computer"]=computer; } // create
         else { params["id"]=id; } // non-create
         params["metadata"]=metadata;
         compl=call_aurora("checkDatasetTemplateCompliance",params);
      } else {
         // this is a non-dataset type template fetching
         if (id ==0) { params["id"]=parent; } // create
         else { params["id"]=id; } // non-create
         params["type"]=type;
         params["metadata"]=metadata;
         compl=call_aurora("checkTemplateCompliance",params);
      }
   }

   // process result of template compliance check
   // if in compliance, execute necessary steps.
   const processCompliance = (result) => {      
      let ok=true;
      // update compliance object with new data
      compliance=result.metadata;
      if (result.compliance == 0) {
         // we have offending key value(s)
         // we are not ok with proceeding
         ok=false;
      }

      // turn off compliance message
      complrunning=false;
      rerender++;

      if (ok) {
         if (id == 0) {
            // create
            createEntity();
         } else {
            // edit
            updateEntity();
         }
      }      
   }

   // show dialog with compliance info for given key
   const complianceInfo = (name) => {     
      sendStatusMessage (name+": \n\n"+compliance[name].comment+"\n\nReason for failure: "+compliance[name].reason+"\n\nRegex: "+compliance[name].regex,"INFO");
   }

   // show dialog with comment info from template for given key
   const templateInfo = (name) => {           
      if ((template[name] != undefined) && (template[name].comment != undefined) && (template[name].comment != "")) {
         sendStatusMessage (name+": \n\n"+template[name].comment+"\n\nRegex: "+template[name].regex,"INFO");
      }   
   }

   // increment counter
   const incCounter = () => {
      pcounter++;
      return "";
   }

   // get current counter without increment
   const getCounter = () => {      
      return pcounter;
   }

   // reset counter
   const resetCounter = () => {
      pcounter=0;
      return "";
   }

   // get a value of a keyed name in array-typecast
   // deriving either from template.default or metadata.value
   const getValue = (name,usetempl=true) => {
      // get the correct value, either from template or metadata
      // we always deal in arrays
      let result=[];
      // pointer to value(s)
      let val;
      // metadata takes precedence on template values
      if (metadata[name] != undefined) {
         val=metadata[name];
      } else if ((usetempl) && (template[name] != undefined)) {
         val=template[name].default;
      }
      if ((!usetempl) && (val == undefined)) { return; }

      // check if value returned is an array or not?
      if (Array.isArray(val) == true) {
         // multiple values, merge metadata array in place
         result.push(...val);
      } else {
         // singular value, add it to array
         result.push(val);
      }      

      // return result array
      return result;
   }

   // get the value of template key
   const getTemplateValue = (name) => {
      // we always deal in arrays
      let result=[];
      // pointer to value(s)
      let val;
      // metadata takes precedence on template values
      if (template[name] != undefined) {
         val=template[name].default;
      }

      // check if value returned is an array or not?
      if (Array.isArray(val) == true) {
         // multiple values, merge metadata array in place
         result.push(...val);
      } else {
         // singular value, add it to array
         result.push(val);
      }      

      // return result array
      return result;      
   }

   // update metadata with changes
   const updateMetadata = (property,index,ev,multiple=false) => {
      let value = ev.target.value;
      // do not update data if value is undefined - skip it
      if (value == undefined) { return; }
      if (metadata[property] == undefined) { metadata[property]=[]; }
      // if already filled with non-array value, convert it to an array
      else if (Array.isArray(metadata[property]) == false) { let v=metadata[property]; metadata[property]=[]; metadata[property][0]=v; }
      if (multiple) {
         // check if value is already present
         // if present, remove it
         let pos = metadata[property].indexOf(value);
         if (pos >= 0) {
            // remove item
            metadata[property].splice(pos,1);
         } else {
            // add item
            metadata[property].push(value);
         }
      } else {
         // add value at index pos
         if (getMax(property) == 1) {
            metadata[property]=value;
         } else {
            metadata[property][index]=value;
         }
      }   
   }

   // get max value of a template key
   const getMax = (name) => {
      // max defaults to 0 (no maximum)
      let max=0;
      if (template[name] != undefined) {
         max=template[name].max;
      }
      return max;
   }

   // get minimum value of a template key
   const getMin = (name) => {
      // min defaults to 0
      let min=0;
      if (template[name] != undefined) {
         min=template[name].min;
      }      
      return min;   
   }

   const cleanMetadata = () => {
      // copy metadata object
      let lmd=JSON.parse(JSON.stringify(metadata));
      // go through object copy and remove keys that are undefined
      let removekeys=[];
      for (let key in lmd) {
         if (Array.isArray(lmd[key])) {
            // this is an array
            let indeces=[];
            for (let i=0; i < lmd[key].length; i++) {
               if (lmd[key][i] == null) {
                  // undefined array element - tag it
                  indeces.push(i);
               }
            }
            // go through each index found and remove it from the lmd hash
            // go top down to avoid issue with shrinking array and stored indeces
            for (let i=indeces.length-1; i >= 0; i--) {
               // remove this element from the lmd hash
               let pos=indeces[i];
               lmd[key].splice(pos,1);
            }            
            if (lmd[key].length == 0) {
               // no entries in current array - tag key for removal
               removekeys.push(key);               
            }         
         } else {
            // this is just a string
            if (lmd[key] == null) {
               // remove this key from hash
               removekeys.push(key);               
            }
         }
      }
      // go through and remove keys tagget for removal
      for (let i=0; i < removekeys.length; i++) {
         let key=removekeys[i];
         delete lmd[key];
      }
      // return resulting object
      return lmd;
   }

   // create an entity
   const createEntity = () => {
      // compliance is ok and we are ready to run 
      // get metadata with null values removed
      let lmd = cleanMetadata();  
      // create-method on REST-server
      create=true;
      let params={};
      params["parent"]=parent;
      params["metadata"]=lmd;
      if ((type.toLowerCase() == "dataset") && (computer != 0)) {
         params["computer"]=computer; 
         params["path"]=path; 
         params["type"]=acquire.toUpperCase();
         params["delete"]=(remove ? 1: 0);
      }
      let etype=type.substring(0,1).toUpperCase()+type.substring(1).toLowerCase();
      created=call_aurora("create"+etype,params);
   }

   // update an entity's metadata
   const updateEntity = () => {
      // compliance is ok and we are ready to run
      let lmd = cleanMetadata();      
      // a metadata update on the entity through the REST-server
      update=true;
      let params={};
      params["id"]=id;
      params["metadata"]=lmd;
      params["mode"]="REPLACE";
      let etype=type.substring(0,1).toUpperCase()+type.substring(1).toLowerCase();
      updated=call_aurora("set"+etype+"Metadata",params);
   }

   // run fininshedHandle callback
   const executeFinishedHandle = () => {
      // only do callback if it is defined
      if (finishedHandle != undefined) {
         finishedHandle();
      }
   }

   // close the MetadaaEditor-component viewing
   const closeEntity = () => {
      // close the viewing of entity metadata
      showresult=false;
      executeFinishedHandle();
      finished=true;      
   }

   // perform tasks after entity was successfully created
   const signalCreated = (result) => {
      // remove result from view
      showresult=false;
      // signal back to caller that we are finished
      executeFinishedHandle();
      finished=true
      // signal back to caller the id of the newly created id
      id=result.id
      // deactivate create
      create=false;
   }

   // perform tasks after entity was successfully updated
   const signalUpdated = (result) => {
      // remove result from view
      showresult=false;
      // get newly created id
      id=result[id];
      // signal back to caller that we are finished
      executeFinishedHandle();
      finished=true;
      // deactivate update
      update=false;
   }

   const getElementClass = (typ,item,index) => {
      if (view) { return ""; }
      let str="";
      if ((typ == "singular") || (typ == "multiple")) {
         if ((compliance[item] != undefined) && (compliance[item].compliance == 0)) {
            str="ui_noncompliance";
         } else if ((template[item] != undefined) && (template[item].flags != undefined) && (template[item].flags.includes("MANDATORY"))) {
            str="ui_mandatory";
         }
      } else {
         // regular input element
         if ((compliance[item] != undefined) && (compliance[item].compliance == 0)) {
            str="ui_noncompliance";
         } else if (((index < getMin(item)) || ((index == 0) && (getMin(item) == 0))) && 
            (template[item] != undefined) && 
            (template[item].flags != undefined) && 
            (template[item].flags.includes("MANDATORY"))) {
            str="ui_mandatory";
         }
      }
      // return result
      return str;
   };

   // initial stuff to do
   operation="Edit";
   if (id == 0) {
      // this is create
      operation="Create";
   } else {
      // this is edit/view - get entity name
      let params={};
      params["id"]=id;
      name=call_aurora("getName",params);   
   }
   if (view) { operation="View"; }

   // add some extra information
   operation=operation+" "+type.toLowerCase();
   if (id != 0) { operation=operation+" ("+id+")"; }

   // fetch data (template and metadata) and merge
   getData();  
</script>

{#if !disabled}
   <!-- Iterate over merged metadata and template and show result --> 
   {#if getdata && templ != undefined}
      {#await templ}      
         <Status message="Loading template..." type="processing" />      
      {:then tresult}
         {#if tresult.err == 0}
            {#if id == 0}
               {merge(tresult)}
            {:else}
               {#await md}
                  <Status message="Loading metadata..." type="processing" />                  
               {:then mresult}
                  {merge(tresult,mresult)}
               {/await}         
            {/if}
         {/if}
      {/await}
   {/if}   
   {#if complrunning && compl != undefined}
      {#await compl}      
         <Status message="Checking metadata compliance..." type="processing" />      
      {:then result}
         {#if result.err == 0}
            { processCompliance(result) }
         {/if}   
      {/await}
   {/if}
   {#if create && created != undefined}
      {#await created}
         <Status message="Creating {type}..." type="processing" />      
      {:then result}
         {#if result.err == 0}
            {signalCreated(result)}
         {/if}   
      {/await}
   {/if}
   {#if update && updated != undefined}
      {#await updated}
         <Status message="Updating {type} ({id}) metadata..." type="processing" />            
      {:then result}
         {#if result.err == 0}
            {signalUpdated(result)}
         {/if}   
      {/await}
   {/if}
   {#if showresult}
      {#key rerender}
         {resetCounter()}
         <div class="ui_title ui_center">{operation}</div> 
         <div class="ui_container">
         {#if view == false}
            <!-- only allow adding keys if view/readonly mode is false -->
            {incCounter()}         
            <div class="ui_label ui_center">Add Metadata Key</div>
            <div class="ui_center">
               <div class="ui_row ui_margin_bottom_large">
                  <div class="ui_input">
                  <input type="text" list={compname+"_datalist_"+getCounter()+"_"+myrand} bind:value={addkey} name="addmdkey" size={93} maxlength={1024}>
                     <datalist id={compname+"_datalist_"+getCounter()+"_"+myrand}>
                        <select size=8>               
                           {#each presetslist as item}
                              <option key={compname+"_"+myrand+"_option_"+getCounter()+"_"+item.id} data-id={item.id} value={item.id}>{item.text}</option>
                           {/each}               
                        </select>           
                     </datalist>
                  </div>
                  <button class="ui_button" on:click={() => { addMetadataKey() }} name={compname+"_addmdkey_"+myrand}><Icon name="add" fill="#FFFFFF" size="24" /></button>                  
               </div>
            </div>
         {/if}
         <!-- Show all relevant keys and input fields for the metadata -->
         {#each mergedkeys as item,i}   
            <!-- svelte-ignore a11y-click-events-have-key-events -->
            <div class="ui_label ui_cursor_pointer ui_center" on:click={templateInfo(item[0])}>{item[0]}</div>
            <!-- Check which type of input this is to be -->
            {#if template[item[0]] != undefined && template[item[0]].flags != undefined && template[item[0]].flags.includes("SINGULAR")}
               <!-- This key has to be a singular value -->
               <div class="ui_center">
                  <div class="ui_row">
                     <div class="ui_select { getElementClass("singular",item[0],i) }">               
                        <select
                           name={compname+"_"+item[0]+"_"+myrand}
                           on:change={(e) => { updateMetadata(item[0],0,e)}}
                           disabled={view}                  
                           style="width: 96ch;" 
                        >
                           <!-- add please-select value -->
                           <option selected={true} value={""} disabled={true} hidden={true}>Please select..</option>
                           <!-- add all values from template -->
                           {#each getTemplateValue(item[0]) as value,index}
                              {incCounter()}
                              <option
                                 name={compname+"_"+item[0]+"_select_"+getCounter()+"_"+myrand}
                                 key={compname+"_"+item[0]+"_select_"+getCounter()+"_"+myrand}
                                 value={value}
                                 disabled={view}
                                 selected={((getValue(item[0],false) != undefined && value == getValue(item[0],false)) ? true : false)}                           
                              >
                                 {value}
                              </option>
                           {/each}
                        </select> 
                     </div>
                     <div class="ui_hidden">
                        <button class="ui_button" name={compname+"_"+item[0]+"_fakekey_"+getCounter()+"_"+myrand} disabled={true}><Icon name="delete" fill="#FFFFFF" size="24" /></button>
                        <button class="ui_button" name={compname+"_"+item[0]+"_fakekey_"+getCounter()+"_"+myrand} disabled={true}><Icon name="delete" fill="#FFFFFF" size="24" /></button>
                     </div>
                  </div>
               </div>
            {:else if template[item[0]] != undefined && template[item[0]].flags != undefined && template[item[0]].flags.includes("MULTIPLE")}
               <!-- This key allows for multiple values -->
               <div class="ui_center">
                  <div class="ui_row">
                     <div class="ui_checkbox { getElementClass("multiple",item[0],i) }" style="width: 88ch;">
                        <checkbox
                           name={compname+"_"+item[0]+"_"+myrand} disabled={view}
                        >
                           {#each getTemplateValue(item[0]) as value,index}
                              {incCounter()}
                              <label>
                                 <input
                                    type="checkbox"
                                    name={compname+"_"+item[0]+"_checkbox_"+getCounter()+"_"+myrand}
                                    key={compname+"_"+item[0]+"_checkbox_"+getCounter()+"_"+myrand}
                                    on:change={(e) => { updateMetadata(item[0],index,e,true); }}
                                    value={value}
                                    checked={(getValue(item[0],false) != undefined && getValue(item[0],false).includes(value) ? true : false)}
                                    disabled={view}>
                                 {value}
                              </label>
                           {/each}
                        </checkbox>                        
                     </div>
                     <div class="ui_hidden">
                        <button class="ui_button" name={compname+"_"+item[0]+"_fakekey_"+getCounter()+"_"+myrand} disabled={true}><Icon name="delete" fill="#FFFFFF" size="24" /></button>
                        <button class="ui_button" name={compname+"_"+item[0]+"_fakekey_"+getCounter()+"_"+myrand} disabled={true}><Icon name="delete" fill="#FFFFFF" size="24" /></button>
                     </div>
                  </div>
               </div>
            {:else} 
               <!-- normal input box, no singular/multiple flags defined -->           
               {#each getValue(item[0]) as value,index}
                  {incCounter()}
                  <div class="ui_center">
                     <div class="ui_input ui_row">                                    
                        <input
                           type="text"
                           class={ getElementClass("input",item[0],index) }
                           name={compname+"_"+item[0]+"_"+getCounter()+"_"+myrand}
                           on:change={(e) => { updateMetadata(item[0],index,e); }}
                           value={value}
                           style="width: 93ch;"                     
                           maxlength={1024}
                           disabled={view}
                           placeholder={(template[item[0]] != undefined ? template[item[0]].comment : "")}
                        >                                          
                        <!-- only show add-button when last value and an addition is allowed by template policy -->
                        {#if !view && index == getValue(item[0]).length-1 && ((getMax(item[0]) == 0) || (index < getMax(item[0])-1)) } 
                           <button class="ui_button ui_half_margin_top"
                              on:click={() => { addMetadataKey(item[0]) }}
                              name={compname+"_addkey_"+item[0]+"_"+getCounter()+"_"+myrand}
                              disabled={view}
                           >
                              <Icon name="add" fill="#FFFFFF" size="24" />
                           </button>
                        {:else}   
                           <div class="ui_hidden"><button class="ui_button ui_half_margin_top" name={compname+"_"+item[0]+"_fakekey_"+getCounter()+"_"+myrand} disabled={true}><Icon name="delete" fill="#FFFFFF" size="24" /></button></div>
                        {/if}
                        {#if !view && ((index >= getMin(item[0]) || (getMin(item[0]) == 0))) && ((getMax(item[0]) == 0) || (getMax(item[0]) > index))}
                           <button
                              class="ui_button ui_half_margin_top"
                              name={compname+"_"+item[0]+"_rmkey_"+getCounter()+"_"+myrand}
                              on:click={() => { removeMetadataKey(item[0],index); }}
                              disabled={view}
                           >
                              <Icon name="delete" fill="#FFFFFF" size="24" />
                           </button>
                        {:else}   
                           <div class="ui_hidden"><button class="ui_button ui_half_margin_top" name={compname+"_"+item[0]+"_fakekey_"+getCounter()+"_"+myrand} disabled={true}><Icon name="delete" fill="#FFFFFF" size="24" /></button></div>
                        {/if}                     
                     </div>
                  </div>
               {/each}            
            {/if}
         {/each}
         <!-- Check if this is a create or not -->
         <div class="ui_center ui_margin_top">      
         {#if id == 0}
            <button class="ui_button" on:click={() => { checkCompliance() }}>Create {type}</button>
         {:else}
            <!-- Check if this is read-only viewing or not -->
            {#if view}
               <button class="ui_button" on:click={() => { closeEntity() }}>Close</button>
            {:else}
               <button class="ui_button" on:click={() => { checkCompliance() }}>Update {type}</button>
            {/if}
         {/if}
         </div>
         </div>    
      {/key}
   {/if}      
{/if}
