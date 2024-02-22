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
    let compname="CodeEditor";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { onMount } from "svelte";

    // some input/output variables
    export let code = "";
    export let numbering = true;
    export let color = "#000000";
    export let backgroundcolor = "#FFFFFF";
    export let numbercolor = "##0060C7";
    export let numberbackgroundcolor = "#555";
    export let startnumber=1;

    // some variables
    let rerender=0;
    let numberarea;
    let textarea;

    // if startnumber changes - update linenumbers
    $: startnumber && textarea != undefined && displayLineNumbers();

    onMount(async () => {
        // render line numbers
        displayLineNumbers();
    });

    // render line numbers starting from start offset
    // defined in startnumber
    const displayLineNumbers = () => {
        const nolines = textarea.value.split('\n').length;
       
        const start = startnumber;
        const end = (start + nolines) - 1;
        let str="";
        let i = start;
        for (let i=start; i <= end; i++) {
            str = str + "<div>" + i + "</div>";
        }
        numberarea.innerHTML = str;
    };

    const keyupHandler = (ev) => {
        // update number of lines
        if (numbering) { displayLineNumbers(); }
    };

    const keydownHandler = (ev) => {       
        if (ev.key === "Tab") {
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;

          textarea.value =
            textarea.value.substring(0, start) +
            "\t" +
            textarea.value.substring(end);

          ev.preventDefault();
        }
    };

    // sync scroll position between text area and line numbering area
    // so that they line numbers line up with the textual lines in the textarea.
    const scrollHandler = (ev) => {    
        // ev.target is the textearea element           
        numberarea.scrollTop = ev.target.scrollTop;            
    }

</script>

<!-- Rendering -->
{#key rerender}
    <div class="codeeditor_editor" style="backgroundcolor: {backgroundcolor}; color: {color};">
        <div class="codeeditor_row">
            <div class="codeeditor_column">
                <div class="codeeditor_linenumbers"
                    bind:this={numberarea}
                    style="backgroundcolor: {numberbackgroundcolor}; color: {numbercolor}"
                />
            </div>
            <div class="codeeditor_column">
                <textarea
                    bind:value={code}
                    cols="150"
                    rows="20"
                    on:keyup={(ev) => { keyupHandler(ev) }}
                    on:keydown={(ev) => { keydownHandler(ev) }}
                    on:scroll={(ev) => { scrollHandler(ev) }}
                    bind:this={textarea}
                />
            </div>
        </div>
    </div>
{/key}

<style>
    .codeeditor_editor {
        display: flex;
        flex-basis: auto;
        font-family: Consolas, "Courier New", Courier, monospace;
    }

    .codeeditor_linenumbers {
        width: 40px;
        text-align: right;
        padding-right: 5px;
        padding-top: 0.22rem;
        overflow: hidden;  
        max-height: 200px;
    }

    .codeeditor_row {
        display: flex;
        justify-content: left;
        align-items:left;
        flex-direction: row;
        text-align: left;
    }

    .codeeditor_column {
        display: flex;
        justify-content: left;
        align-items:left;
        flex-direction: column;
        text-align: left;
    }

    .codeeditor_editor textarea {
        border: none;
        width: 100%;
        overflow: scroll;
        resize: none;
        max-height: 200px;
        white-space: pre;
    }
    
    .codeeditor_editor textarea:focus {
        border-color: #000000;
        color: #000000;    
    }
</style>
