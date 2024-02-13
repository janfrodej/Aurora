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
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script> 
 
<script>  
  import { onMount } from 'svelte';
  import { getConfig } from "./_config";    
  import Icon from "./Icon.svelte";
  import SQLStructRenderer from "./SQLStructRenderer.svelte";
  import { PRESETS_SYSTEM } from './_sysschema';
  import { hash2SortedSelect,sendStatusMessage } from './_tools';
  
  // component name
  let compname="SQLStructEditor";
  // create a random id number of this instance of component
  let myrand = counter++;
  // config settings
  let CFG={};
  // some internal variables
  let disabled=false;

  export let sqlstruct = [];
  export let update = 0;

  // internal variables
  let selected = sqlstruct;  
  let parent = sqlstruct;
  let rerender;
  let showkey = false;
  let compareel;
  let presetlist=hash2SortedSelect(PRESETS_SYSTEM);
  let addkey = "";
  let orgroup = false;

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
  let copslist = Object.keys(cops);

  onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // set disabled
      disabled = (CFG["www.maintenance"] != undefined ? CFG["www.maintenance"] : false);
  });    

  const valuesExists = (src,list) => {
    let exists = false;
    // create source list
    let srclist = Object.keys(src);
    list.forEach((item) => {
      if (srclist.includes(item)) { exists = true; }      
    });
    return exists;
  }

  const addAndGroup = () => {
    // add a and-group on the
    // currently selected element
    if (Array.isArray(selected)) {
      // array - add to end
      let group={};
      selected.push(group);
      // force rerender
      rerender++;      
    } else {
      // cannot add a and-group on such a element     
      sendStatusMessage("It is not allowed to add an AND-group on this element.");      
    }

  };

  const addOrGroup = () => {
    if (Array.isArray(selected)) {
      let group=["OR"];
      selected.push(group);
      // force rerender
      rerender++;          
    } else if (typeof selected == "object") {
      // this is a hash, use keyname
      let group=["OR"];
      selected[addkey] = group;
      showkey = false;
      orgroup = false;
      // force a rerender
      rerender++;           
    }
  };

  const addOrGroupSelector = () => {
    // check of we are adding list on array or hash
    if (Array.isArray(selected)) {
      // we are adding it on a array, go to adding it
      addOrGroup();
    } else if ((typeof selected == "object") && (!valuesExists(selected,copslist))) {
      // this is a hash without comparison operators, ask for keyname
      orgroup = true;
      showkey = true;     
    } else {
      // we are not allowed
      sendStatusMessage("It is not allowed to add an OR-group on this element.");      
    }

  };

  const showKeyHash = () => {
    // ask for key name
    // ensure that selected structure is ok
    // and that it is not a structure of comparison operators
    if ((!Array.isArray(selected)) && (typeof selected == "object") && (!valuesExists(selected,copslist))) {
      showkey = true;     
    } else {
      // not allowed
      sendStatusMessage("It is not allowed to add a key->value on this element.");
    } 
  }

  const handleAddKey = (ev) => {
    // check for enter or no key-event at all
    if (ev.keyCode == 13) {        // enter key
      if (addkey != "") { 
        if (!orgroup) { addKeyValue(); }
        else { addOrGroup(); }
      } else {
        showkey = false;        
      } 
      addkey = "";  
    } else if (ev.keyCode == 27) { // ESC key
      showKey = false;
    }
  };

  const addKeyValue = () => {
    // add given key to selected structure
    showkey = false;
    selected[addkey] = { "=": "" };
    // force rerender
    rerender++;    
  };

  // add a comparison operator, only on a hash
  const addComparator = (ev) => {
    // get comparison operator
    let cop = ev.target.value;
    // the element needs to either be a hash that do not have the cop already OR
    // it needs to be an array where the parent is a hash (and thereby containing the key-name)
    if ((!Array.isArray(selected) && (typeof selected == "object") && (!selected.hasOwnProperty(cop))) || 
        ((Array.isArray(selected)) && ((!Array.isArray(parent)) && (typeof parent == "object")))) {
        if (Array.isArray(selected)) {
          // add a hash structure in addition to the comparison operator
          let group={};        
          group[cop] = "";
          selected.push(group);
        } else {
          // only add the comparison operator on a hash
          selected[cop] = "";
        }      
      // force a rerender
      rerender++;  
    } else {      
      // not allowed with comparison operator
      sendStatusMessage("It is not allowed to add comparison operator on this element or operator already exists.");      
    }
    // reset index of select-list      
    compareel.selectedIndex = 0;
  };

  const closeAddKey = () => { 
    addkey = "";
    showkey = false;
  }

</script>

{#key update}
  <!-- show editor symbols -->
  <div class="ui_center ui_margin_top ui_sqlstruct_editbar">
    <div class="ui_sqlstruct_editbar_items">
      <!-- svelte-ignore a11y-click-events-have-key-events -->
      <div class="ui_sqlstruct_editbar_icon" title="Logical AND-group" on:click={() => { addAndGroup() }}>(&#x22C0)</div>
      <!-- svelte-ignore a11y-click-events-have-key-events -->
      <div class="ui_sqlstruct_editbar_icon" title="Logical OR-group" on:click={() => { addOrGroupSelector() }}>(&#x22C1)</div>
      <!-- svelte-ignore a11y-click-events-have-key-events -->
      <div class="ui_sqlstruct_editbar_icon" title="Add key->value" on:click={() => { showKeyHash() }}><Icon name="plus" size="40" fill="#FFFFFF#" /></div>
      <div class="ui_sqlstruct_editbar_icon" title="Add comparison operator">
        <select bind:this={compareel} on:change={(ev) => { addComparator(ev) }}>
          <option value="NONE" hidden={true} selected={true}>&#62|&#60</option>
          {#each copslist as cop}
            <option value="{cop}">{cops[cop]}</option>
          {/each}
        </select>
      </div>
    </div>  
  </div>  

  <div class="ui_row ui_margin_top" title="Heeeelp!"><a href={CFG["www.helppages"]+"#how-to-do-advanced-search"} target="_aurora_search_doc">How to do advanced search</a></div>

  {#if showkey}
    <div class="ui_margin_top ui_sqlstruct_key_label">Add key with name:</div>
    <div class="ui_sqlstruct_key_input ui_margin_top">
      <input class="ui_input" type="text" list="sqlstructeditor_preset_list_{myrand}" bind:value={addkey} on:keypress={(ev) => handleAddKey(ev) } size={32} maxlength={1024} selected={true}>
      <datalist id="sqlstructeditor_preset_list_{myrand}">
        <select size=8>               
            {#each presetlist as item}
              <option key={compname+"_"+myrand+"_presetlist_"+item.id} data-id={item.id} value={item.id}>{item.text}</option>
            {/each}
        </select>           
      </datalist>
      <button on:click={() => { closeAddKey() }}>X</button>
      <button on:click={() => { let ev={}; ev.keyCode=13; handleAddKey(ev); }}>Add</button>
    </div>  
  {/if}

  <!-- <button on:click={() => { console.log("SQLSTRUCT:"); console.log(sqlstruct); } }>SHOW SQLSTRUCT</button> -->
  <!-- <button on:click={() => { console.log("JSON SQLSTRUCT:"); console.log(JSON.stringify(sqlstruct)); } }>SHOW JSON</button> -->

  <!-- show the rendering of the SQLStruct -->
  <div class="ui_margin_top ui_left">
    <SQLStructRenderer sqlstruct={sqlstruct} bind:selected={selected} bind:parentselected={parent} bind:rerender={rerender} />
  </div>
{/key}
