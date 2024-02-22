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
  // component name
  let compname="Modal";
  // create a random id number of this instance of component
  let myrand = counter++;
  // some internal variables
  
  // exported variables of component
  // background color of modal
  export let background="#CCCCCC";
  // text-color in modal
  export let color="#555";
  // to show a border around the modal or not
  export let border=false;
  // border color if used
  export let border_color;
  // border width if used
  export let border_width;
  // border style if used
  export let border_style;
  // top, fixed position in percent, just a digit
  export let top;
  // bottom, fixed position in percent, just a digit
  export let bottom;
  // right, fixed position in percent, just a digit
  export let right;
  // left, fixed position in percent, just a digit
  export let left;
  // width of modal, supersedes top, bottom, right and left
  export let width;
  // height of modal, supersedes top, bottom, right and left
  export let height;
  // z-index of modal, if any. Defaults to 10.
  export let zindex;
  // if scrolling is enabled for x direction
  export let horizontal_scroll = true;
  // if scrolling is enabled for y direction
  export let vertical_scroll = true;
  // show a shadow on the modal or not. Undefined triggers a default box shadow,
  // blank string disables it and if set should be in the format of the css box-shadow
  // property.
  export let boxshadow;
  // callback handler for closing the modal, triggered by the close button on the modal
  export let closeHandle;

  const handleClose = () => {
      if (closeHandle != undefined) {
          // run close handle
          closeHandle();
      }
  }

  // normalize value to between 1 and 100 (percent)
  const normalize = (val) => {
    // if value is undefined, we do not touch it
    if (val == undefined) { return val; }
    // typecast value to integer
    val=Math.floor(Number(val));
    // check the values boundaries and adjust accordingly
    if (val > 100) { val=100; }
    if (val < 1) { val=1; }
    // return the new value
    return val;
  }

  const calculatePosition = () => {
    // init vars for top, bottom, left and right
    let t,b,l,r;
    // width and height have presedence on top, bottom etc..        
    if ((width != undefined) || (height != undefined)) {
        // normalize values before proceeding
        width=normalize(width);
        height=normalize(height);
        // calculate top
        t=String(Math.floor((100-(height||80))/2)) + "%";
        // bottom same as top
        b=t;
        // calculate left
        l=String(Math.floor((100-(width||80))/2)) + "%";
        // right same as left
        r=l;    
    } else if ((top != undefined) || (bottom != undefined) ||
               (left != undefined) || (right != undefined)) {
        // we have values on at least one attribute, the rest we default
        // normalize all values before proceeding
        top=normalize(top);
        bottom=normalize(bottom);
        left=normalize(left);
        right=normalize(right);
        // define the right attribute values
        t=String(top||10) + "%";        
        b=String(bottom||10) + "%";
        l=String(left||10) + "%";
        r=String(height||10) + "%";
    } else {
        // we have no values - use defaults
        t="10%"; b=t; l=t; r=t;
    }
    // return the result in css notation
    return "top: "+t+"; bottom: "+b+"; left: "+l+"; right: "+r+";";
  }

// get the shadow of the modal, if any
const getShadow = () => {
    if (boxshadow == undefined) {
        // no shadow defined - we default
        return "box-shadow: 5px 10px 8px 10px #888888;";
    } else {
        // we have a shadow setting - return it...
        if (boxshadow == "") { return ""; }
        else { return "box-shadow: "+boxshadow+";"; }
    }
}

const getBorder = () => {
    let result="";
    if (border) {
        let w="border-width: "+(border_width||"1") + "px;";
        let s="border-style: "+(border_style||"solid") + ";";
        let c="border-color: "+(border_color||"#000000") + ";";
        result=w+s+c;
    }    
    // return the border values, if any
    return result;
}

</script>

<div class="modal_overlay" style="{zindex ? 'zindex: '+(Number(zindex)-1)+';' : 'z-index: 9;'}">
    <div class="modal_container" style="color: {color}; 
                                background: {background}; 
                                {calculatePosition()}
                                {getBorder()} 
                                {getShadow()}
                                {zindex ? 'z-index: '+Number(zindex)+';' : 'z-index: 10;'}                             
    ">
    <div class="modal_close_button"><button on:click={() => { handleClose() }}>X</button></div>
    <div class="modal_body" style="overflow-x: {(horizontal_scroll ? "auto" : "hidden")};
                                   overflow-y: {(vertical_scroll ? "auto" : "hidden")};">
        <slot /> 
    </div>
    </div>
</div>

<style>
    .modal_overlay {
        position: fixed;
        display: block;        
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(128,128,128,0.5);
    }

    .modal_container {
        position: fixed;  
        display: block;  
    }

    .modal_body {
        margin-top: 10px;
        margin-bottom: 10px;
        margin-left: 10px;
        margin-right: 10px;                
        width: 93%;
        height: 93%;
    }

    .modal_close_button {
        float: right;
        clear: both;
        margin-right: 10px;
        margin-top: 5px;
    }
    
</style>
