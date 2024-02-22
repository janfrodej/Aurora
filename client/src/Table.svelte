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

    Description: Show and handle a table arrangement based upon table input.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script> 
 
<script>  
  import { hash2SortedArray, numberedHash2Array, sortArray } from "./_tools.js";
  import Icon from './Icon.svelte';
   
  // component name
  let compname="Table";
  // create a random id number of this instance of component
  let myrand = counter++;
  // some internal variables
  let order=[];
  let orderby;
  
  // exported variables of component
  export let headers={};
  export let data={};
  export let disabled=false;
  export let orderdirection=-1;
  export let sorthandler;
  //
  // color css options
  //
  // --header_color="#000099";
  // --header_background="#CCCCCC";
  // --cell_color="#000099";
  // --row_even_background="#BBBBBB";
  // --row_odd_background="#DDDDDD";
  // --select_color="#000000";
  // --select_background="#6F6F6F";
  
  // orders the table rows based upon
  // the numbered keys of the hash
  const orderTableRows = (hash) => {
    // sort key in hash    
    order=numberedHash2Array(hash);
  }

  // order the rows coming in from data by whatever field of choice
  orderTableRows(data);

  const getFieldValue = (field,keyno) => {
    // check if this field has a dataconverter function
    // if so, invoke it
    let datavalue=data[keyno][field.dataname];
    if (field.dataconverter != undefined) {
        // conversion is to take place for this field, run callback function
        return field.dataconverter(datavalue,data[keyno]);
    } else {
        // no conversion on this field, return value as is
        return (datavalue != undefined ? datavalue : "");
    }
  }

  const getMenuValue = (menu) => {
    if (menu.name == undefined) {
        return "";        
    } else {
        // return the menu option name
        return menu.name;
    }
  }

  // handle an on-click event on a dropdown and
  // run callback for that select.
  // ev - event data for the select change event
  // field - header definition hash structure for the row in question
  // index - the index in the menu hash-structure that was selected
  // key - key into data structure for the row in question
  const handleMenuSelect = (ev,field,index,key) => {
    // only run callback if disabled is false
    // undefined is the same as false
    if ((field.menu[index] != undefined) && (field.menu[index].action != undefined)) {
        // we are ready to run callback
        field.menu[index].action(field,field.menu[index],data[key]);
    }
    // reset selectedindex to first element       
    // if first menu element is hidden (meaning its not a normal dropdown menu)
    if (((ev.target.options != undefined) && (ev.target.options["0"].hidden)) ||
        (ev.target.parentElement.firstChild.hidden)) {
        // this works for Firefox
        ev.target.parentElement.selectedIndex = 0;             
        // this works for Chrome
        if (ev.target.options != undefined) { ev.target.options.selectedIndex = 0; }
    }    
    return;
  }

  const handleMenuDisabled = (field,menuitem,key) => {
    // run menu callback and get status back if specific menu option
    // is disabled for this row or not    
    return menuitem.disabled(field,menuitem,data[key]);    
  }
  
</script>

<div class="Table_table">
    <!-- show all table headers -->
    {#each headers.fields as field}
        {#if field.visible}
            <div class="Table_table_header_cell">
                <!-- svelte-ignore a11y-click-events-have-key-events -->
                <div class="Table_table_cursor" on:click={() => {if (sorthandler != undefined) { sorthandler(field.dataname,orderdirection); }}}>
                   {field.name} {(headers.orderby == field.dataname ? (orderdirection == -1 ? String.fromCharCode(8744) : String.fromCharCode(8743)) : "")}
                </div>   
            </div>    
        {/if}
    {/each}
    <!-- show all rows of data -->            
    {#each order as item,orderindex}
        <!-- this is a new row -->
        <!-- eheck if this is an even or odd row -->            
        <div class="Table_table_row {(headers.oddeven ? (orderindex % 2 == 0 ? "Table_table_even" : "Table_table_odd") : "")}">        
            <!-- go through each field of row and process all that are to be visible -->
            {#each headers.fields as field}        
                {#if field.visible}
                    <!-- this is a visible row, check if it is a menu or not -->
                    <div class="Table_table_cell">
                        {#if field.menu != undefined && field.menu.length > 0}
                            <!-- this is to be drawn as a dropdown-menu and not just a value -->
                            <select class="Table_table_select" on:click={(ev) => { handleMenuSelect(ev,field,ev.target.value,item[0]) }} disabled={disabled}>
                                {#each field.menu as menuitem,index}
                                    {#if menuitem.disabled != undefined}
                                        <option value={index} disabled={handleMenuDisabled(field,menuitem,item[0])}                                         
                                        hidden={(menuitem.hidden != undefined ? menuitem.hidden : false)} 
                                        selected={(menuitem.selected != undefined ? menuitem.selected : false)}>{getMenuValue(menuitem)}</option>
                                    {:else}
                                        <option value={index}>{getMenuValue(menuitem)}</option>
                                    {/if}    
                                {/each}
                            </select>
                        {:else}   
                            {#if field.image != undefined}
                                <div class="ui_row">
                                    {#each sortArray(Object.keys(field.image),undefined,false) as image,index}
                                        {#if field.imagevisible !== undefined && field.imagevisible(field,index,data[item[0]])}
                                            <!-- callback defined and it says true to displaying image -->
                                            <div class="ui_table_padding_left">
                                            <img src={field.image[index].src} alt={field.image[index].alt} title={field.image[index].alt} height="20">
                                            </div>
                                        {/if}
                                        {#if field.imagevisible === undefined}                                    
                                            <!-- no visible callback defined, image is always visible -->
                                            <img src={field.image[index].src} alt={field.image[index].alt} title={field.image[index].alt} height="20">
                                        {/if}
                                    {/each}
                                </div>
                            {/if}    
                            {#if field.icon != undefined}                            
                                <div class="ui_row">
                                    {#each sortArray(Object.keys(field.icon),undefined,false) as icon,index}
                                        {#if field.iconvisible !== undefined && field.iconvisible(field,index,data[item[0]])}
                                            <!-- callback defined and it says true to displaying icon -->
                                            <div class="ui_table_padding_left">
                                                <Icon name={field.icon[index].name} 
                                                      size={field.icon[index].size||20} 
                                                      fill={field.icon[index].fill||"#000000"} 
                                                      popuptext={field.icon[index].description} 
                                                />                                            
                                            </div>
                                        {/if}
                                        {#if field.iconvisible === undefined}                                    
                                            <!-- no visible callback defined, icon is always visible -->
                                            <Icon name={field.icon[index].name} 
                                                  size={field.icon[index].size||20} 
                                                  fill={field.icon[index].fill||"#000000"} 
                                                  popuptext={field.icon[index].description} 
                                            />
                                        {/if}
                                    {/each}
                                </div>                            
                            {/if}   
                            {#if field.image === undefined && field.icon === undefined}
                                <!-- this is just a value to be shown, ensure conversion if necessary -->                           
                                {getFieldValue(field,item[0])}
                            {/if}    
                        {/if}
                    </div>                    
                {/if}
            {/each}
        </div>    
    {/each}    
</div>

<style>    
    .Table_table {
      display: table;
      margin-top: 20px;
      width: 90%;
      margin-left: 5%;
      margin-right: 5%;
    }       
    
    .Table_table_row {
       display: table-row;
       padding: 2px;
    }
    
    .Table_table_even {       
       background-color: var(--row_even_background,#BBBBBB);
    }
        
    .Table_table_odd {       
       background-color: var(--row_odd_background,#DDDDDD);       
    }
    
    .Table_table_header_cell {
       display: table-cell;
       padding: 10px;
       white-space: nowrap;
       text-align: left;
       background-color: var(--header_background,#CCCCCC);
       color: var(--header_color,#000099);
       font-weight: bold;
    }
    
    .Table_table_cell {
       display: table-cell;   
       text-align: left;
       padding: 10px;
       vertical-align: middle;
       color: var(--cell_color,#000099);
    }    

    .Table_table_select {
       -webkit-appearance: none;
       -moz-appearance: none;
       appearance: none;
       background-color: var(--select_background,#6F6F6F);
       color: var(--select_color,#000000);
       text-align: center;
       font-weight: bolder;
       width: 30px;
       border: none;
    }        

    .Table_table_cursor {
        cursor: default;
    }
</style>
    
