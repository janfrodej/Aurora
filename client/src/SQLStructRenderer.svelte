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

    Description: Render a SQLStruct search-structure. See the REST documentation of the AURORA REST-server for more information on SQLStruct.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script> 
 
<script>  
  // SQLStructRenderer - a module to render SQLStruct-structures and work on them.
  // The module uses svelte-recursion on the component itself to render the structure.

  import { onMount } from 'svelte';
  import { getConfig } from "./_config"; 
  import { PRESETS_SYSTEM } from './_sysschema';
  import { hash2SortedSelect, sortArray } from './_tools';
   
  // component name
  let compname="SQLStructRenderer";
  // create a random id number of this instance of component
  let myrand = counter++;
  // Config of AURORA
  let CFG={};
  // some internal variables
  let disabled=false;
  // preset-list for keys
  let presetlist=hash2SortedSelect(PRESETS_SYSTEM);

  // the SQLStruct structure
  // two-way 
  export let sqlstruct = [];  // the SQLstruct we are working on in this component-call
  export let parentsqlstruct = sqlstruct; // the possible parent to the sqlstruct
  export let keyname = ""; // keyname/index from parent
  export let gfsqlstruct = sqlstruct; // the possible grandfather to the sqlstruct
  export let gfsqlindex; // the index into the grandfather
  export let rerender = 0; // rerender counter that are bound all the way from root parent and down to all children
                           // this means an update on the rerender-variable in any of the children of the component
                           // will force a rerender of the whole SQLStruct structure.
  export let level = 0; // current structure level
  export let selected = sqlstruct; // the currently selected element in the sqlstruct
  export let parentselected = sqlstruct; // the currently selected elements parent
  
  // allowed logical operator in SQLStruct
  let lops = {
      "AND": "AND",
      "OR": "OR",
      "NOT": "NOT",     
  };
  // lets also have a list of the logical operators
  let lopslist = Object.keys(lops);
  // allowed comparison operators in SQLStruct
  let cops = {
    ">" : ">",
    "<" : "<",
    "<>": "<>",
    "=" : "=",
    ">=": ">=",
    "<=": "<=",
    "!" : "IS NOT",
    "-" : "NOT",
    "&" : "BITWISE AND",
    "|" : "BITWISE OR",
    "^" : "BITWISE XOR",
  };
  // make a list of the comparison operators
  let copslist = Object.keys(cops);
  // allowed filters in SQLStruct
  let filters = {
    0 : "NONE",
    1 : "ISO8601 to UNIX DATETIME",
    2 : "BYTE DENOMINATOR to BYTES",    
  }
  
  onMount(async () => {
    // fetch configuration and wait
    CFG =  await getConfig();
    // update disabled
    disabled = (CFG["www.maintenance"] != undefined ? CFG["www.maintenance"] : false);
  });  

  // update the sqlstruct with the new value
  const updateValue = (ev,struct,index) => {
    if (Array.isArray(struct)) {
      // this is an array
      struct[index] = ev.target.value;
    } else if (typeof struct == "object") {
      // this is a hash
      struct[index] = ev.target.value;
    } else if (typeof struct == "string" || typeof struct == "number") {
      // this is a string or number
      struct = ev.target.value;
    }
    // rerender structure
    rerender++;   
    return "";
  }  

  const updateFilterValue = (ev,struct,name) => {
    let filter = ev.target.value;    
    // set filter value for the filter
    struct["#"+name] = filter;
    // force rerender of parent component and down
    // by changing the rerender value that is bound
    // all the way up to the parent
    rerender++;
    
    return "";
  };

  const updateKey = (ev,structparent,oldname) => {
    let newname = ev.target.value;
    // first check if key actually changed
    if (newname != oldname) {
      // a change occured - check if key already exists
      // we are not allowed to use existing key names
      if (structparent[newname] == undefined) {
        // does not exist - add/update
        structparent[newname] = structparent[oldname];
        // delete old key from hash
        delete structparent[oldname];
        // check if we have filter info
        // if so, save it
        if (structparent["#"+oldname] != undefined) {
          // set the old value on the new name
          structparent["#"+newname] = structparent["#"+oldname];
          // delete the old key
          delete structparent["#"+oldname];
        }
        // force rerender of parent component and down
        // by changing the rerender value that is bound
        // all the way up to the parent
        rerender++;
      } else {
        // key already exists - notify?
        rerender++;
      }
    }
    return "";
  };

  // check a keyname that it it does not contain any characters that 
  // we would like it not to, such as being like a COP.
  // if ok, invoke updateKey-function.
  const checkKey = (ev,structparent,oldname) => {
    let newname = ev.target.value;    
    // check if value contains any illegal characters, such as COPs:
    let exists = false;
    for (let i=0; i < copslist.length; i++) {
      if (newname == copslist[i]) { exists = true; break; }
    }
    // only update key if it is not like any of the COPs
    if (!exists) { updateKey (ev,structparent,oldname); }
    else {
      // if we do not desire any change, just force a rerender from struct 
      rerender++;
    }
  };

  // remove an item and the group if empty
  // struct = structure that is the root of the item to remove
  // pkey = is the parental key/index that holds the item to be removed
  // key = the key/item to be removed, sometimes omitted
  const removeItem = (struct,pkey,key,gfstruct,gfindex) => {
    if ((key != undefined) && (pkey != undefined)) {
      // removal on the parent structure
      delete struct[pkey][key];      
      // check if structure is empty, then remove parent itself
      // this can never be true for arrays that contain the LOP on index 0
      if ((!Array.isArray(struct[pkey])) && (typeof struct[pkey] == "object") && (Object.keys(struct[pkey]).length == 0)) {
        // the structure is empty, delete the parental item that holds it
        delete struct[pkey];
        delete struct["#"+pkey];
        if ((gfstruct[gfindex] == struct) && (Object.keys(struct).length == 0)) {          
          // remove the grandfather item holding the parental key
          if (Array.isArray(gfstruct)) {
            // grandfather is an array, use splice
            gfstruct.splice(gfindex,1);
          } else { delete gfstruct[gfindex]; }
        }  
      } 
      // force rerender
      rerender++;
    } else if ((key == undefined) && (pkey != undefined)) {
      // removal on the current level, check if array or not
      if (Array.isArray(struct)) {
        // this is an array, use splice
        struct.splice(pkey,1);
      } else {
        // this is a hash, delete the key
        delete struct[pkey]; 
        // also delete the filter
        delete struct["#"+pkey];
      }
      // force rerender
      rerender++;
    } 
    return "";
  };

  // set the currently selected element in the 
  // SQLStruct structure upon exiting/de-focusing it.
  // We also save previously selected element as the 
  // parentelement.
  // These are also exporeted outside the component through the 
  // selected-variable and parentselected-variable respectively.
  const setSelectedElement = (element,parent) => {
    // set selected to the element
    selected = element;
    parentselected = parent;
  };

</script>

<!-- LOP = Logical Operator -->
<!-- COP = Comparison Operator -->

{#if !disabled}
  {#key rerender}
    <!-- check if the start of the sqlstruct is an array or a hash(object) or not -->
    {#if Array.isArray(sqlstruct)}
      <!-- this is an array -->    
      <div class="ui_margin_left">      
        <!-- start the array block here-->
        <!-- svelte-ignore a11y-no-noninteractive-tabindex -->
        <div class="ui_column  ui_padding {(level % 2 == 0 ? "ui_sqlstruct_list_even" : "ui_sqlstruct_list_odd")}" tabindex={level} on:blur={() => { setSelectedElement(sqlstruct,parentsqlstruct); }}>
          <!-- check if sqlstruct and its parent are not the same (ie root-node) -->  
          {#if sqlstruct != parentsqlstruct && sqlstruct.length > 0}
            <button on:click={() => { removeItem(parentsqlstruct,keyname,undefined,gfsqlstruct,gfsqlindex) }}>X</button>
          {/if}
          <!-- check if parent is a hash, if so add the keyname -->  
          {#if !Array.isArray(parentsqlstruct) && typeof parentsqlstruct == "object"}  
            <input type="text" value={keyname} on:blur={(ev) => { checkKey(ev,parentsqlstruct,keyname); setSelectedElement(sqlstruct,parentsqlstruct); }}>        
          {/if}
          {#each sqlstruct as item, index}
            <!-- check if index is 0 or not, because in an array that is the LOP -->        
              {#if index == 0}
                <!-- this is the LOP of the group -->
                <div class="ui_row">
                  <div class="ui_sqlstruct_paranthesis">(
                    <select on:change={(ev) => { updateValue(ev,sqlstruct,index); }} on:blur={() => { setSelectedElement(sqlstruct,parentsqlstruct); }} disabled={level == 0 ? true : false}>
                      {#each lopslist as lop}          
                        <option value={lop} selected={String(item).toLowerCase() == String(lop).toLowerCase() ? true : false}>
                          {lops[lop]}
                        </option>
                      {/each}
                    </select>
                  </div>
                </div>  
              {:else}
                <!-- recurse through the rest of the array -->            
                <div class="ui_padding {Array.isArray(sqlstruct) ? (level % 2 == 0 ? "ui_sqlstruct_list_even" : "ui_sqlstruct_list_odd") : (typeof sqlstruct == "object" ? (level % 2 == 0 ? "ui_sqlstruct_hash_even" : "ui_sqlstruct_hash_odd") : "")}">
                <svelte:self sqlstruct={item} keyname={index} parentsqlstruct={sqlstruct} gfsqlstruct={parentsqlstruct} gfsqlindex={keyname} bind:rerender={rerender} bind:selected={selected} bind:parentselected={parentselected} level={level+1} />
                <div class="ui_sqlstruct_lop">{index < Object.entries(sqlstruct).length - 1 ? (String(sqlstruct[0]).toUpperCase() == "OR" ? "OR" : "AND") : ""}</div>
                </div>
              {/if}
              {#if index == sqlstruct.length-1}
                <div class="ui_sqlstruct_paranthesis">)</div>
              {/if}             
          {/each}  
        </div>   
      </div>
    {:else if typeof sqlstruct == "object"}
      <!-- this is a hash or object -->      
      <!-- svelte-ignore a11y-no-noninteractive-tabindex -->
      <div class="ui_margin_left ui_padding {(level % 2 == 0 ? "ui_sqlstruct_hash_even" : "ui_sqlstruct_hash_odd")}" tabindex={level} on:blur={() => { setSelectedElement(sqlstruct,parentsqlstruct); }}>
        <div class="ui_row">
          <button on:click={() => { removeItem(parentsqlstruct,keyname,undefined,gfsqlstruct,gfsqlindex) }}>X</button>
          {#if !Array.isArray(parentsqlstruct) && keyname != "" && !/^\#.*$/.test(keyname)}
            <input type="text" value={keyname} list={compname+"_"+myrand+"_presetlist"} on:blur={(ev) => { checkKey(ev,parentsqlstruct,keyname); setSelectedElement(sqlstruct,parentsqlstruct); }}>            
            <datalist id={compname+"_"+myrand+"_presetlist"}>
              <select size=8>               
                  {#each presetlist as item}
                    <option key={compname+"_"+myrand+"_presetlist_"+item.id} data-id={item.id} value={item.id}>{item.text}</option>
                  {/each}
              </select>           
            </datalist>
            <select on:change={(ev) => { updateFilterValue(ev,parentsqlstruct,keyname); }}>
              {#each sortArray(Object.keys(filters)) as filter}
                <option value={filter} 
                  selected={parentsqlstruct["#"+keyname] != undefined ? (parentsqlstruct["#"+keyname] == filter ? true : false) : (filter == 0 ? true : false)} 
                >
                  {filters[filter]}
                </option>                  
              {/each}
            </select>
          {/if}  
          <div class="ui_sqlstruct_paranthesis">(</div>
        </div>
      {#each Object.entries(sqlstruct) as [key,value], index (key)}
        {#if !/^\#.*$/.test(key) && (Array.isArray(value) || typeof value == "object")}          
          <!-- this needs to further recursing, include name of key -->                     
          <svelte:self sqlstruct={sqlstruct[key]} keyname={key} parentsqlstruct={sqlstruct} gfsqlstruct={parentsqlstruct} gfsqlindex={keyname} bind:rerender={rerender} bind:selected={selected} bind:parentselected={parentselected} level={level+1} />                              
          <div class="ui_sqlstruct_lop">{index < Object.entries(sqlstruct).length - 1 ? "AND" : ""}</div>                    
        {:else if !/^\#.*$/.test(key)}
          <!-- this is a straigth forward hash key->value statement and can be rendered -->          
          {#if copslist.includes(key)}
            <!-- this key is a comparison operator and keyname was delivered as a parameter to this component -->
            {#if keyname != ""}
              <div class="ui_row {(level % 2 == 0 ? "ui_sqlstruct_hash_even" : "ui_sqlstruct_hash_odd")}">              
                <div class="ui_margin_left">
                  <button on:click={() => { removeItem(parentsqlstruct,keyname,key,gfsqlstruct,gfsqlindex) }}>X</button>
                  <select on:change={(ev) => { updateKey(ev,sqlstruct,key); }}>
                    {#each copslist as cop}
                      <option value={cop} selected={key == cop ? true : false}>
                        {cops[cop]}
                      </option>
                    {/each}          
                  </select>                      
                  <input type="text" bind:value={sqlstruct[key]} on:blur={() => { setSelectedElement(sqlstruct,parentsqlstruct); }}> <div class="ui_sqlstruct_lop">{index < Object.entries(sqlstruct).length - 1 ? "AND" : ""}</div>
                </div>
              </div>
            {/if}
          {:else}
            <!--this key is not a comparison operator, but a key name -->
            <!-- since it is neither an array or object and only key->value, the only possible COP is equal (=) -->
            <button on:click={() => { removeItem(sqlstruct,key,undefined,gfsqlstruct,gfsqlindex) }}>X</button><input type="text" bind:value={key}>
            <select on:change={(ev) => { updateFilterValue(ev,parentsqlstruct,key); }}>
              {#each sortArray(Object.keys(filters)) as filter}
                <option value={filter} 
                  selected={parentsqlstruct["#"+key] != undefined ? (parentsqlstruct["#"+key] == filter ? true : false) : (filter == 0 ? true : false)} 
                >
                  {filters[filter]}
                </option>                  
              {/each}
            </select>  
            <select>            
              <option value={"="} disabled={true} selected={true}>
                {"="}
              </option>            
            </select>    
            <input type="text" bind:value={sqlstruct[key]}>
          {/if}        
        {/if}     
      {/each}
      <div class="ui_sqlstruct_paranthesis">)</div></div>
    {:else if typeof sqlstruct == "string" || typeof sqlstruct == "number"}  
      <!-- this is a string or number and only that -->
      <button on:click={() => { removeItem(parentsqlstruct,keyname,undefined,gfsqlstruct,gfsqlindex) }}>X</button><input type="text" bind:value={sqlstruct}>
    {/if}
  {/key}
{/if}
