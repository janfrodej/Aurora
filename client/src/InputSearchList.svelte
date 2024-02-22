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

    Description: Show a selection dropdown box with the option to function as both a search box and a regular selection box.
-->
<script context="module">
   // unique counter for instances of component
   let counter = 0;
</script> 
   
<script>  
   import { createEventDispatcher, afterUpdate } from 'svelte';
   import Icon from './Icon.svelte';
   // component name
   let compname="InputSearchList";
   // create a random id number of this instance of InputSearchList
   let myrand = counter++;
   // option-click event name
   //let opclickevent=compname+"_"+myrand+"_option_click";
   // default value to use in input field
   export let defaultValue;
   // default internal/textual value
   export let defaultTextValue;
   // input datalist, if any
   export let datalist; 
   datalist = (datalist == undefined ? [] : datalist);
   // input datalist id, must be unique
   export let datalistid;
   datalistid=(datalistid == undefined ? compname+"_datalist_"+myrand : datalistid);
   // variable holding the chosen or written value, set to default at beginning
   export let value = (defaultValue != undefined ? defaultValue : (datalist == undefined || datalist[0] == undefined || datalist[0].id == undefined ? -1 : datalist[0].id));
   defaultValue=value;
   // also export the textual value chosen
   export let textValue = (defaultTextValue != undefined ? defaultTextValue : undefined);
   // toggle if multiple values can be selected or not
   export let multiple = false;
   // set visible size of input in characters
   export let size;
   // set maximum number of characters allowed
   let maxchars=524288;
   export let maxlength = maxchars; // defaults by spec to 524288
   // make possible to keep focus markings on input box, even when not focused
   export let keepfocus = false;
   // only allow list values to be written in the input box
   // this will have effect on de-focus of the input box, where it will be reset to 
   // blank if not contanining valid value.
   export let onlylist=false;   
   // internal, display value
   let intvalue = (defaultTextValue != undefined ? defaultTextValue : undefined );
   // reference to input element
   let inputel;  
   // reference to select element
   let selectel;
   // reference to datalist element
   let datalistel;   
   // dropdown icon element
   let dropdownel;
   // dropdown toggle
   let dropdowntoggle = false;
   // know if we are hovering over dropdown icon or not
   let iconhovering = false;
  
   const dispatch = createEventDispatcher();

   afterUpdate(() => {
      // value is the id-attribute of datalist,
      // needs to be matched with datalist.   
      datalist.forEach((item) => {
         if ((item.id == value) && (intvalue != item.text)) {     
            intvalue=item.text;        
         }
      });            
   });

   // find maximum number of characters used
   const findMaxCharacters = () => {
      let max=0;   
      datalist.forEach(el => {
         let len=el.text.length;
         if ((len > max) && (len <= maxchars)) { max=len; }       
      });
      // return result
      return max;
   }

   // set size to maximum number of characters if not set
   size=(size == undefined ? findMaxCharacters() : size); 
   
   // ensure that we always deal in ids when exporting
   // values while at the same time only displaying 
   // the textual values on screen.
   const handleChange = (e) => {
      // get the id from the choice in the datalist    
      let txt="";
      let val=e.target.value||"";

      // make regexp to find relevant data
      let re=/^(.*)\s+\(([^\)]+)\)$/;
      // attempt to match
      let res=val.match(re);
      // retrieve matching sub-groups
      txt=(res != undefined ? res[1] : val);
      val=(res != undefined ? res[2] : val);
      
      if (txt != undefined) {
         // set exported value to the datalist key id
         value=val;
         // set the display value to the relevant text
         intvalue=txt;
         // set the textvalue
         textValue=txt;
      } else { value=undefined; }
   }

   const handleOnlyList = (e) => {
      // go through each datalist item and
      // reset component value if needed
      let val=e.target.value;
      if (onlylist) {
         let found=false;
         datalist.forEach((item) => {
            if (item.text == val) {     
               found=true;
            }
         });   
         // check if written value is within bounds
         // if not, reset it
         if (!found) { value=undefined; intvalue=undefined; }
      }
   }

   // handles events fired by the component
   // the component forwards: focus, input,
   // change, onblur, select, click and dblclick
   // to the degree that various browsers fire them
   const handleEvent = (type,data) => {    
      switch (type) {
         case "click" :
            // check that we are not hovering over the 
            // dropdown when clicking here, but technically it 
            // should not be possible when generating this event....
            // reset dropdowntoggle var because dropdown is closed....
            if (!iconhovering) { dropdowntoggle=false; }
            break;
         case "focus" :
            // stuff to do inside component
            selectel.style.display='';
            break;
         case "input" :
            handleChange(data);
            // reset dropdowntoggle when selecting a 
            // value or writing a value
            dropdowntoggle=false;
            break;      
         case "blur" :
            handleOnlyList(data);
            // if we are outside icon when losing
            // focus, we reset the dropdowntoggle var
            if (!iconhovering) { dropdowntoggle=false; }
            break;
      }     

      // send event outside component
      dispatch (type,data.detail);
   }

   const toggleDropdown = () => {
      // check if we are to open or close dropdown      
      if (!dropdowntoggle) {
         // open dropdown - it is closed (false)
         inputel.value="";
         //selectel.value="";
         inputel.focus();
         datalistel.style.display="block";
         datalistel.style.display="none";
         datalistel.blur();      
      } else {
         // close dropdown - it is open (true)
         inputel.blur();       
      }
      // toggle the dropdown flag itself
      dropdowntoggle=!dropdowntoggle;  
   }
</script>

<div class="inputsearchlist_row">
   <input type="text" on:focus={(e) => {handleEvent("focus",e)}} on:input={(e) => {handleEvent("input",e)}} on:change={(e) => {handleEvent("change",e)}} on:blur={(e) => {handleEvent("blur",e)}} on:select={(e) => {handleEvent("select",e)}} on:click={(e) => {handleEvent("click",e)}} on:dblclick={(e) => {handleEvent("dblclick",e)}} bind:this={inputel} list={datalistid} class='inputsearchlist_input {keepfocus ? "inputsearchlist_keepfocus" : ""}' bind:value={intvalue} size={size} maxlength={maxlength}>
   <datalist bind:this={datalistel} id={datalistid}>
      <select class="inputsearchlist_select" bind:this={selectel} multiple={multiple} size=8>
         {#if defaultValue == undefined && defaultTextValue != undefined}         
            <option key={compname+"_"+myrand+"_option_default"} selected={true}>{defaultTextValue}</option>
         {/if}
         {#each datalist as item}         
            <option key={compname+"_"+myrand+"_option_"+item.id} data-id={item.id} value={item.text+" ("+item.id+")"} selected={defaultValue == item.id ? true : false}>{item.text} ({item.id})</option>
         {/each}
      </select>   
   </datalist>
   <!-- only show dropdown arrow if browser is Firefox. Chrome and Edge supply their own... -->
   {#if /Firefox/.test(window.navigator.userAgent) }
      <!-- svelte-ignore missing-declaration -->
      <!-- svelte-ignore a11y-click-events-have-key-events -->
      <div class="inputsearchlist_icon" bind:this={dropdownel} on:click={() =>{ toggleDropdown() }}>
         <Icon name="arrowdown" fill="#000000" size="20" bind:hovering={iconhovering} />
      </div>
   {/if}
</div>

<style>
   datalist { display: none }

   .inputsearchlist_input {
      display: inline-block;  
   }

   .inputsearchlist_select {
      display: none;
   }

   .inputsearchlist_keepfocus {
      outline: 2px solid orange;      
   }

   .inputsearchlist_row {
      position: relative;
      display: flex;
      justify-content: left;
      z-index: 1;
      align-items:left;
      flex-direction: row;
      text-align: left;
   }

   .inputsearchlist_icon {
      position: absolute; 
      top: 0; 
      border-radius: 10px; 
      right: 0px; 
      border: none;
      z-index: 10; 
      top: 1.5em; 
      height: 20px; 
      color: black; 
      background-color: white; 
      transform: translateX(-3px);
   }
</style>
