---
title: "Kela lexicon"
---

{{ $data := index .Site.Data.kela }}

<table class="lexicon">
  <thead>
    <tr>
      <th scope="col">lemma</th>
      <th scope="col">gloss</th>
      <th scope="col">class</th>
      <th scope="col">notes</th>
    </tr>
  </thead>
  <tbody>
    {{ range $data }}
    <tr>
      <td>{{ .lemma }}</td>
      <td>{{ .gloss }}</td>
      <td>{{ with .class }}{{ . }}{{ end }}</td>
      <td>{{ with .notes }}{{ . }}{{ end }}</td>
    </tr>
    {{ end }}
  </tbody>
</table>
