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

    Description: Handle showing some content floating over the web-page.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script> 
 
<script>       
  // component name
  let compname="FloatContent";
  // create a random id number of this instance of component
  let myrand = counter++;
  // some internal variables
  
  // exported variables of component
  
  // width of modal, supersedes top, bottom, right and left
  export let width;
  // height of modal, supersedes top, bottom, right and left
  export let height;
  // z-index of modal, if any. Defaults to 10.
  export let zindex;
  
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

</script>

<div class="floatcontent_overlay" style="{zindex ? 'zindex: '+(Number(zindex)-1)+';' : 'z-index: 9;'}">    
    <div class="ui_center_row">
        <slot />    
    </div>
</div>

<style>
    .floatcontent_overlay {
        position: fixed;
        display: block;        
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(128,128,128,0.5);
    }
</style>
