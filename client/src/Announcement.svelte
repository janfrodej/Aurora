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
    let compname="Announcement";
    // create a random id number of this instance of component
    let myrand = counter++;        
    import { onMount } from 'svelte';

    // number of announcements to show, newer to older
    // a setting of 0 means show all....
    export let visibleCount = 5;

    let show = false;
    let messages = [];

    onMount(async () => {
      // fetch configuration and wait      
      let m = await getAnnouncements();
      if (m.length > 0) { show = true; }
    });

    async function getAnnouncements (location=window.location.origin+window.location.pathname+"/announcement.log") {
        const res=await fetch(location, 
            {
                method: "POST",          /* HTTP method */
                credentials: "omit",     /* do not send cookies */
                mode: "cors",            /* its a cross origin request */
                headers: { 
                        "User-Agent": "SvelteAuroraWebClient/1.0B",
                        "Content-Type": "application/text",
                        "Accept": "application/text",
                        },
            }
            )
            .then((response) => { return response; }
            ); 

        await res;

        // convert body to text
        let text = await new Response(res.body).text(); 
        // convert announcement entries into an array
        let found = text.match(/^([^\s]+\s+[^\s]+)\s+([^\r\n]+)[\n\r]+(.*)$/s);
        while (found != null) {
            let datetime = found[1];
            let message = found[2];

            // construct object with information for this message
            let o = { datetime: datetime, message: message };

            // add message to messages array
            messages.push(o);

            // update text
            text = found[3] || "";
            // update found
            found = text.match(/^([^\s]+\s+[^\s]+)\s+([^\r\n]+)[\n\r]+(.*)$/s);
        }    
        // return messages
        return messages;
    }
</script>

{#if show}
    <div class="ui_margin_top">
        <div class="ui_label ui_center">
            Announcements
        </div>
        <div class="ui_announcements">
            {#each messages.reverse() as item, index}
                {#if index < visibleCount || visibleCount == 0}
                    <div class="ui_announcements_row">
                        <div class="ui_announcements_datetime">{item.datetime}</div>
                        <div class="ui_announcements_message">{item.message}</div>
                    </div>
                {/if}
            {/each}
        </div>
    </div>
{/if}
