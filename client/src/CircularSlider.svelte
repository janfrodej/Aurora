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

    Description: Component to show one circular slider, set its boundaries and what to display etc.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script> 
 
<script>  
  import { onMount } from 'svelte';
   
  // component name
  let compname="CircularSlider";
  // create a random id number of this instance of component
  let myrand = counter++;  
  // rerender variable
  let rerender=0;
  // sets if slider has been selected
  let selected = false;

  // exported variables of component
  export let size = 300;                // size of svg window square
  export let color = "black";           // color of slider circle
  export let tipcolor = color;          // color of slider tip, default to same as color
  export let tipwidth = 6;              // slider tip circle diameter
  export let stroke_width = 3;          // stroke width of slider circle
  export let stroke_linecap = "round";  // capping at the end of the stroke
  export let stroke_dasharray = "1";    // the dash style of the stroke
  export let legend = true;             // show legend or not
  export let legendcolor = color;       // separate color-choice for legend possible, default to color.
  export let legendpos = "top";         // position of value legend. Correct values are top, bottom, left, right and center
  export let legendfont = "sans-serif"; // set font to use for legend.
  export let legendfontsize = 30;       // set font size of legend.
  export let legendstrokewidth = 2;     // stroke width used for drawing legend text.
  export let values = [];               // array with values to slide through, none if auto-generated numbers
  export let value = "";                // chosen value on the slider, can be preset
  export let index = -1;                // index of chosen value from values-array
  export let valuetype = "number";      // type of values. Acceptable values are: number and array. Defaults to number
  export let min = 0;                   // min value to use - reference to values-array position. Please note when auto-generated 
                                        // refers to the minimum acceptable value of slider.
  export let max = 0;                   // max value to use - reference to values-array position. Please note when auto-generated 
                                        // refers to the maximum acceptable value of slider.

  let padding = 10;
  let ax = padding;
  let ay = (size / 2);
  let diameter = size - padding;
  let radius = diameter / 2;
  let center = (size / 2);
  let hpadding = padding / 2;  

  // run when starting the component
  onMount(async () => {
    // check values, type, min and max
    valuetype = (valuetype != undefined ? valuetype : "number");
    valuetype = (String(valuetype).toLowerCase() == "number" ? "number" : "array");
    if (!Array.isArray(values)) { values = []; }
    min = (typeof min == "number" ? min : 0);
    max = (typeof max == "number" ? max : 0);
    if ((valuetype == "number") && (values.length == 0)) {
        // user has specified numbers as the values, but no input array - generate it        
        for (let i=min; i <= max; i++) {
            // add value to array
            values.push(i);
        }      
    } 
    // double check min and max that they have sensible values
    if (min < 0) { min = 0; }
    if (max >= values.length) { max = values.length - 1; }
    // check legend position
    legendpos = (legendpos == undefined ? "top" : String(legendpos).toLowerCase());
    if ((legendpos != "top") &&
        (legendpos != "bottom") &&
        (legendpos != "left") &&
        (legendpos != "right") &&
        (legendpos != "center")) {
            // default to top if none of position values are acceptable
            legendpos = "top";
    }
    // check legendfontsize, set default if not correct type
    if (typeof legendfontsize != "number") { legendfontsize = 30; }
    // if value is different from blank (its preset), get its index in values and 
    // then calculate its x and y-value
    if ((value != "") && (value != undefined)) {
        let idx = values.indexOf(value)
        if (idx > -1) {
            // value was found in values-array - calculate its slider position
            // circle = (x−xc)2 + (y−yc)2 = r2, which gives y = yc + scrt(r2 - (x-xc)2).            
            let half = Math.floor(values.length / 2); // all values are divided on two halves of the circle
            let x = 0;
            let y = 0;
            if (idx < half) {
               // we are within 180 degrees of the circle
               x = hpadding + ((diameter / half) * idx);                 
               y = center - Math.sqrt(radius**2 - (x - center)**2);
            } else {
               // we have passed over 180 degrees of the circle
               x = (size - hpadding) - ((diameter / half) * (idx - half));
               y = center + Math.sqrt(radius**2 - (x - center)**2);
            }
            // update ax and ay with calculated values
            ax = x;
            ay = y;
            index = idx;
            value = values[idx];            
        }
    }    
  });

  // move the slider as the mouse moves, calculate
  // y-axis endpoint based upon x-position.
  const moveSlider = (ev) => {    
    if (selected) {
        // get SVG-element from event
        let svg;    
        if ((ev.target != undefined) && 
            (ev.target.constructor.name == 'SVGSVGElement')) {        
            svg = ev.target;
        }    
        if (svg != undefined) {            
            const pt = svg.createSVGPoint();            
            pt.x = ev.clientX;
            pt.y = ev.clientY;        
            const loc = pt.matrixTransform(svg.getScreenCTM().inverse());
            // set x to the z-location in the svg view
            ax = loc.x;
            // find y based on x movement in svg window
            // circle = (x−xc)2 + (y−yc)2 = r2, which gives y = yc + scrt(r2 - (x-xc)2).            
            if (loc.y <= center) {
                // we have not passed beyond center in y coordinate
                ay = center - Math.sqrt(radius**2 - (ax - center)**2);
            } else {
                // we have passed center in y coordinate - add center to result
                ay = center + Math.sqrt(radius**2 - (ax - center)**2);            
            }        
            // find value chosen in
            // values-array
            let vcount = values.length;
            let vcounthalf = vcount / 2;
            let pos = 0;
            // find where we are in the values array based on where we are on the circular slider
            if (ay > center) { pos = (((size - hpadding) - ax) / (diameter / vcounthalf)) + vcounthalf; }
            else { pos = (ax - hpadding) / (diameter / vcounthalf); }
            // round down
            pos = Math.floor(pos);
            if (pos >= vcount) { pos = vcount - 1; }
            // only update if the value have changed and is not undefined
            // also set index at the same time to tell which array element is selected
            if ((value != values[pos]) && (values[pos] != undefined)) { index = pos; value = values[pos]; }
        }
    }
  };

  // toggle setting the slider or not.
  const selectToggle = (ev) => {
    selected = !selected;
  };  

  const textMetrics = (text) => {
    let font = legendfontsize + "pt " + legendfont;
    let canvas = document.createElement("canvas");
    let context = canvas.getContext("2d");
    context.font = font;
    let metrics = context.measureText(text);
    return metrics;
  };

  const textWidth = (text) => {    
    return textMetrics(text).width;
  };  

</script>

{#key rerender}
   <span>
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <svg            
            width={size}
            height={size}
            fill="none"
            stroke={color}
            stroke-width={stroke_width}            
            stroke-dasharray={stroke_dasharray}
            stroke-linecap={stroke_linecap}
            on:mousemove={(ev) =>{ moveSlider(ev); }}
            on:click={(ev) => { selectToggle(ev); }}            
            xmlns="http://www.w3.org/2000/svg">      
            {#if ay <= center}
                {#if ax <= center}            
                    <path d="M {hpadding} {center}
                             A {radius} {radius} 0 0 1 {ax} {ay}"/>
                {:else}
                    <path d="M {hpadding} {center}
                             A {radius} {radius} 0 0 1 {center} {hpadding}
                             A {radius} {radius} 0 0 1 {ax} {ay}"/>
                {/if}
            {:else} 
                <path d="M {hpadding} {center}
                         A {radius} {radius} 0 0 1 {center} {hpadding}
                         A {radius} {radius} 0 0 1 {size-hpadding} {center}"/>
                {#if ax >= center}
                    <path d="M {size-hpadding} {center}
                             A {radius} {radius} 0 0 1 {ax} {ay}"/>
                {:else}
                    <path d="M {size-hpadding} {center}
                             A {radius} {radius} 0 0 1 {center} {size-hpadding}
                             A {radius} {radius} 0 0 1 {(ax < hpadding ? hpadding : ax)} {ay}"/>
                {/if}
            {/if}
            <circle cx={ax} cy={ay} r={5} stroke={tipcolor} stroke-width={tipwidth} stroke-dasharray="0"/>
            {#if legend}
                {#if legendpos == "bottom"}
                    <text
                        x={center - (textWidth(value) / 2) + padding}
                        y={size-hpadding-40}
                        font-family={legendfont}
                        font-size={legendfontsize}
                        stroke={legendcolor}
                        stroke-width={legendstrokewidth}
                        stroke-dasharray="0"
                        fill={legendcolor}
                    >
                        {value}
                    </text>
                {/if}
                {#if legendpos == "left"}
                    <text
                        x={30}
                        y={center + (legendfontsize / 2)}
                        font-family={legendfont}
                        font-size={legendfontsize}
                        stroke={legendcolor}
                        stroke-width={legendstrokewidth}
                        stroke-dasharray="0"
                        fill={legendcolor}
                    >
                        {value}
                    </text>
                {/if}
                {#if legendpos == "right"}
                    <text
                        x={size - hpadding - 10 - textWidth(value)}
                        y={center + (legendfontsize / 2)}
                        font-family={legendfont}
                        font-size={legendfontsize}
                        stroke={legendcolor}
                        stroke-width={legendstrokewidth}
                        stroke-dasharray="0"
                        fill={legendcolor}
                    >
                        {value}
                    </text>
                {/if}
                {#if legendpos == "top"}
                    <text
                        x={center - (textWidth(value) / 2) + padding}
                        y={60}
                        font-family={legendfont}
                        font-size={legendfontsize}
                        stroke={legendcolor}
                        stroke-width={legendstrokewidth}
                        stroke-dasharray="0"
                        fill={legendcolor}
                    >
                        {value}
                    </text>
                {/if}
                {#if legendpos == "center"}
                    <text
                        x={center - (textWidth(value) / 2) + padding}
                        y={center + (legendfontsize / 2)}
                        font-family={legendfont}
                        font-size={legendfontsize}                        
                        stroke={legendcolor}
                        stroke-width={legendstrokewidth}
                        stroke-dasharray="0"
                        fill={legendcolor}
                    >
                        {value}
                    </text>
                {/if}            
            {/if}
        </svg>
    </span>
{/key}
