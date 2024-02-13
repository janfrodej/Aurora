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
  import InputSearchList from "./InputSearchList.svelte";
  import { hash2SortedSelect } from "./_tools.js";  
  import { date2Unixtime, timezoneStr, unixtime2Date } from './_iso8601';
   
  // component name
  let compname="DateTimeSlider";
  // create a random id number of this instance of component
  let myrand = counter++;
  // some internal variables
  let yearlist=[];
  let monthlist=[];
  let daylist=[];
  let hourlist=[];
  let minlist=[];
  let seclist=[];
  // which input element is selected
  let selected; 
  // if range slider is enabled or not?
  let rangedisabled=true;
  // ptr to range slider
  let rangeel; 
  // get current time
  let time=unixtime2Date();
  // get the timezone in effect
  let timezone=timezoneStr();
  // get current full year
  let fullyear=time.getFullYear();
  let curmonth=time.getMonth();
  let curday=time.getDay();
  // legend for the slider
  let legend="";
  // rerender variable
  let rerender=0;

  // exported variables of component
  // min and max year to generate
  export let minyear=2000;
  export let maxyear=2050;
  // set datetime in unixtime utc
  export let datetime;
  // set start year
  export let year;
  // if year has not been specified, we assume the 
  // year is current year provided it is within the minyear/maxyear scope
  year = (year == undefined ? (fullyear >= minyear && fullyear <= maxyear ? fullyear : minyear) : year);
  // set initial month if not set
  export let month=1;
  // set initial day
  export let day=1;
  // set initial hour
  export let hour=8;
  // set initial minute
  export let min=0;
  // set initial sec
  export let sec=0;
  
  // get datetime from input
  const getDateTime = () => {
    let dt=unixtime2Date(datetime);
    // we convert to display/locale time
    year=dt.getFullYear();
    month=dt.getMonth()+1;
    day=dt.getDate();
    hour=dt.getHours();
    min=dt.getMinutes();    
    sec=dt.getSeconds();    
  }

  // put datetime of component back into datetime
  // variable
  const putDateTime = () => {
    let dt=new Date();
    dt.setFullYear(year != undefined ? year : fullyear);
    dt.setMonth((month != undefined ? month-1 : curmonth));
    dt.setDate(day||curday);
    dt.setHours(hour != undefined ? hour : 12);
    dt.setMinutes(min != undefined ? min : 0);
    dt.setSeconds(sec != undefined ? sec : 0);
    // set utc unixtime
    datetime=date2Unixtime(dt);
  }

  // adjust year, month etc. based on datetime
  // datetime takes precedence over all other props
  if (datetime != undefined) { datetime=Math.floor(Number(datetime)); getDateTime() }
  else { putDateTime() }
  
  onMount(async () => {
    // generate the list of years
    let years={};
    for (let year=minyear; year <= maxyear; year++) {
      years[year]=String(year);
    }    
    yearlist=hash2SortedSelect(years);    
    // generate the list of months
    let months={};
    for (let month=1; month <= 12; month++) {
      months[month]=String(month);
    }
    monthlist=hash2SortedSelect(months,undefined,undefined,false);
    // generate list of days
    let days={};
    for (let day=1; day <= 31; day++) {
      days[day]=String(day);
    }
    daylist=hash2SortedSelect(days,undefined,undefined,false);
    // generate list of hours    
    let hours={};
    for (let hour=0; hour <= 23; hour++) {
      let hourstr="";
      if ((hour >= 0) && (hour <= 9)) {
        hourstr="0"+String(hour);
      } else {
        hourstr=String(hour);
      }
      hours[hour]=hourstr;
    }
    hourlist=hash2SortedSelect(hours);
    // generate list of minutes
    let mins={};
    for (let min=0; min <= 59; min++) {
      let minstr="";
      if ((min >= 0) && (min <= 9)) {
        minstr="0"+String(min);
      } else {
        minstr=String(min);
      }
      mins[min]=minstr;
    }
    minlist=hash2SortedSelect(mins);
    // generate list of seconds    
    let secs={};
    for (let sec=0; sec <= 59; sec++) {
      let secstr="";
      if ((sec >= 0) && (sec <= 9)) {
        secstr="0"+String(sec);
      } else {
        secstr=String(sec);
      }
      secs[sec]=secstr;
    }
    seclist=hash2SortedSelect(secs);
    // rerender all the components to get the new values
    rerender+=1;    
  });  


  // check which input element was selected and set slider
  // accordingly
  const selectInput = (elem) => {
    // find out which input element was selected
    selected=elem;
    switch (elem) {
      case 1 :
        rangeel.min=yearlist[0].id;
        rangeel.max=yearlist[yearlist.length-1].id;   
        rangeel.value=year;   
        legend=rangeel.min+" - "+rangeel.max;        
        break;
      case 2 :
        rangeel.min=monthlist[0].id;
        rangeel.max=monthlist[monthlist.length-1].id;      
        rangeel.value=month;  
        legend=rangeel.min+" - "+rangeel.max;        
        break;
      case 3 :
        rangeel.min=daylist[0].id;
        rangeel.max=daylist[daylist.length-1].id;        
        rangeel.value=day;
        legend=rangeel.min+" - "+rangeel.max;        
        break;
      case 4 : 
        rangeel.min=hourlist[0].id;
        rangeel.max=hourlist[hourlist.length-1].id;        
        rangeel.value=hour;
        legend=rangeel.min+" - "+rangeel.max;        
        break;
      case 5 :
        rangeel.min=minlist[0].id;
        rangeel.max=minlist[minlist.length-1].id;        
        rangeel.value=min;
        legend=rangeel.min+" - "+rangeel.max;        
        break;
      case 6 :
        rangeel.min=seclist[0].id;
        rangeel.max=seclist[seclist.length-1].id;        
        rangeel.value=sec;
        legend=rangeel.min+" - "+rangeel.max;        
        break;
      default :
        break;
    }
  
    rangedisabled=false;
  }

  // update value that comes from slider
  // and set the corresponding input element 
  // accordingly
  const updateInputValue = (value) => {
    switch (selected) {
      case 1 :
        year=value;
        putDateTime();
        break;
      case 2 :        
        month=value;
        putDateTime();
        break;
      case 3 :
        day=value;
        putDateTime();
        break;
      case 4 :
        hour=value;
        putDateTime();
        break;
      case 5 :
        min=value;
        putDateTime();
        break;
      case 6 :
        sec=value;
        putDateTime();
        break;
      default :
        break;
    }    
  }
  
</script>

{#key rerender}
  <div class="datetimeslider_container"> 
    <div class="datetimeslider_table">
      <div class="datetimeslider_table_body">
        <div class="datetimeslider_table_row">
          <div class="datetimeslider_table_cell datetimeslider_legend">
            Year
          </div>
          <div class="datetimeslider_table_cell">&nbsp;</div>
          <div class="datetimeslider_table_cell datetimeslider_legend">
            Month
          </div>
          <div class="datetimeslider_table_cell">&nbsp;</div>
          <div class="datetimeslider_table_cell datetimeslider_legend">
            Day
          </div>          
          <div class="datetimeslider_table_cell">
            &nbsp
          </div>
          <div class="datetimeslider_table_cell datetimeslider_legend">
            Hour
          </div>
          <div class="datetimeslider_table_cell">&nbsp;</div>
          <div class="datetimeslider_table_cell datetimeslider_legend">
            Minute
          </div>
          <div class="datetimeslider_table_cell">&nbsp;</div>
          <div class="datetimeslider_table_cell datetimeslider_legend">
            Second
          </div>        
        </div>
        <div class="datetimeslider_table_row">
          <div class="datetimeslider_table_cell">
            <InputSearchList onlylist={true} on:blur={() => updateInputValue(year) } on:focus={() => { selectInput(1) }} bind:value={year} datalist={yearlist} defaultValue={year} size={4} maxlength={4} keepfocus={selected == 1 ? true : false} />          
          </div>
          <div class="datetimeslider_table_cell">
            -
          </div>
          <div class="datetimeslider_table_cell">
            <InputSearchList onlylist={true} on:blur={() => updateInputValue(month) } on:focus={() => { selectInput(2) }} bind:value={month} datalist={monthlist} defaultValue={month} size={2} maxlength={2} keepfocus={selected == 2 ? true : false} />
          </div>
          <div class="datetimeslider_table_cell">
            -
          </div>
          <div class="datetimeslider_table_cell">
            <InputSearchList onlylist={true} on:blur={() => updateInputValue(day) } on:focus={() => { selectInput(3) }} bind:value={day} datalist={daylist} defaultValue={day} size={2} maxlength={2} keepfocus={selected == 3 ? true : false} />
          </div>  
          <div class="datetimeslider_table_cell">
            T
          </div>
          <div class="datetimeslider_table_cell">
            <InputSearchList onlylist={true} on:blur={() => updateInputValue(hour) } on:focus={() => { selectInput(4) }} bind:value={hour} datalist={hourlist} defaultValue={hour} size={2} maxlength={2} keepfocus={selected == 4 ? true : false} />
          </div>
          <div class="datetimeslider_table_cell">
            :
          </div>
          <div class="datetimeslider_table_cell">
            <InputSearchList onlylist={true} on:blur={() => updateInputValue(min) } on:focus={() => { selectInput(5) }} bind:value={min} datalist={minlist} defaultValue={min} size={2} maxlength={2} keepfocus={selected == 5 ? true : false} />
          </div>    
          <div class="datetimeslider_table_cell">
            :
          </div>
          <div class="datetimeslider_table_cell">
            <InputSearchList onlylist={true} on:blur={() => updateInputValue(sec) } on:focus={() => { selectInput(6) }} bind:value={sec} datalist={seclist} defaultValue={sec} size={2} maxlength={2} keepfocus={selected == 6 ? true : false} />
          </div>        
        </div>                          
      </div>
    </div>    
    <input class="datetimeslider_slider" type="range" bind:this={rangeel} on:change={(e) => { updateInputValue(e.target.value) }} min="1" max="100" value="50" id="myRange" disabled={rangedisabled}>        
    <div class="datetimeslider_legend">({legend})</div> 
  </div>
{/key}

<style>

  .datetimeslider_container {
    width: 60%;
    margin-top: 20px;
    display: flex;
    justify-content: center;
    align-items:center;
    flex-direction: column;

  }

  /* The slider itself */
  .datetimeslider_slider {
    -webkit-appearance: none;  /* Override default CSS styles */
    appearance: none;
    width: 80%; /* Full-width */
    height: 25px; /* Specified height */
    background: #d3d3d3; /* Grey background */
    outline: none; /* Remove outline */
    opacity: 0.7; /* Set transparency (for mouse-over effects on hover) */
    -webkit-transition: .2s; /* 0.2 seconds transition on hover */
    transition: opacity .2s;
    margin-top: 20px;
  
    /* border: 2px;
    border-radius: 10px;*/
  }

  /* Mouse-over effects */
  .datetimeslider_slider:hover {
    opacity: 1; /* Fully shown on mouse-over */
  }

  /* The slider handle (use -webkit- (Chrome, Opera, Safari, Edge) and -moz- (Firefox) to override default look) */
  .datetimeslider_slider::-webkit-slider-thumb {
    -webkit-appearance: none; /* Override default look */
    appearance: none;
    width: 25px; /* Set a specific slider handle width */
    height: 25px; /* Slider handle height */
    background: #555; 
    cursor: pointer; /* Cursor on hover */
  }

  .datetimeslider_slider::-moz-range-thumb {
    width: 25px; /* Set a specific slider handle width */
    height: 25px; /* Slider handle height */
    background: #555; 
    cursor: pointer; /* Cursor on hover */
  }

  .datetimeslider_legend {
    margin-top: 20px;
    font-weight: bold;
  }

  .datetimeslider_table {
      display: table;
      margin-top: 20px;
      width: 90%;
      margin-left: 5%;
      margin-right: 5%;      
    }
    
  .datetimeslider_table_body {
    display: table-row-group;
  }
  
  .datetimeslider_table_row {
      display: table-row;
      padding: 2px;
  }
    
  .datetimeslider_table_cell {
      display: table-cell;
      white-space: nowrap;
      text-align: center;
      padding: 10px;
      vertical-align: middle;
      color: #000099;
  }

</style>
