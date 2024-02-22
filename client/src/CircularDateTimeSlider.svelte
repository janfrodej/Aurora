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

    Description: Show a circular slider arrangement for setting/adjusting year, month and date.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script> 
 
<script>  
    import CircularSlider from './CircularSlider.svelte';
    import { date2Unixtime, unixtime2Date } from './_iso8601';
        
    // component name
    let compname="CircularDateTimeSlider";
    // create a random id number of this instance of component
    let myrand = counter++;  
    // rerender variable
    let rerender=0;
    // sets if slider has been selected
    let selected = false;

    // exported variables of component
    export let datetime = 0;              // unix datetime - default 0 or 1970-01-01

    // define values and month-span
    let year = unixtime2Date(datetime).getFullYear();
    let month = unixtime2Date(datetime).getMonth();
    let day = unixtime2Date(datetime).getDate();    
    const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];    

    const recalculate = () => {
        // create Date-instance set to year, month and day of sliders, normalized to 12 midday.
        let date = new Date(Date.parse(year + "-" + String(month + 1).padStart(2,"0") + "-" + String(day).padStart(2,"0") + "T12:00:00"));
        // update datetime with the new date-instance value
        datetime = date2Unixtime(date);
    };

    // recalculate the exported datetime variable
    // each time one of the sliders change value
    $: year && (recalculate());
    $: (month || month == 0) && (recalculate());
    $: day && (recalculate());

</script>

{#key rerender}
    <div style="display: flex; " class="ui_margin_top">
    <!-- year -->       
    <span style="display: flex; flex-direction: column">
        <div class="ui_label">Year</div>
        <CircularSlider
            size={180}
            color="#555"
            legendpos="center"
            stroke_dasharray="10,10"
            stroke_width=6
            bind:value={year}
            min={2018}
            max={new Date().getFullYear() + 20}
        />    
    </span>
    <!-- month -->
    <span style="display: flex; flex-direction: column">
        <div class="ui_label">Month</div>
        <CircularSlider
            size={180}
            color="#555"
            legendpos="center"
            stroke_dasharray="10,10"
            stroke_width=6
            value={months[month]}
            bind:index={month}
            values={months}
            valuetype="array"
        />
    </span>
    <!-- day -->
    <span style="display: flex; flex-direction: column">
        <div class="ui_label">Day</div>
        <CircularSlider
            size={180}
            color="#555"
            legendpos="center"
            stroke_dasharray="10,10"
            stroke_width=6
            bind:value={day}
            min={1}
            max={31}
        />
    </span>
    </div>
{/key}
