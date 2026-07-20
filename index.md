---
layout: default
title: Coloring Room
---

<section class="hero" aria-labelledby="hero-title">
  <div class="hero__copy">
    <p class="eyebrow">iPad + Apple Pencil <span aria-hidden="true">·</span> Fullscreen coloring</p>
    <h1 id="hero-title">A coloring room built around the pencil.</h1>
    <p class="hero__lede">Choose a scene, draw and fill with native PencilKit tools, organize your library, and send finished artwork to a gallery or share-ready PNG.</p>
    <div class="hero__actions">
      <a class="button button--primary" href="{{ site.github_url }}">View on GitHub <span aria-hidden="true">↗</span></a>
      <a class="button button--quiet" href="#studio-flow">Enter the studio</a>
    </div>
    <ul class="signal-list" aria-label="Project foundation">
      <li>SwiftUI</li><li>PencilKit</li><li>80 templates</li><li>Offline-first</li>
    </ul>
  </div>
  <aside class="status-card" aria-labelledby="build-status-title">
    <div class="status-card__topline"><span class="status-pill"><span class="status-dot" aria-hidden="true"></span>{{ site.status_label }}</span><span class="status-card__meta">iPad first</span></div>
    <div class="house-mark" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
    <p class="status-card__kicker">Current experience</p>
    <h2 id="build-status-title">Choose the page.<br>Make it completely yours.</h2>
    <dl class="status-list">
      <div><dt>Built-in scenes</dt><dd>80</dd></div>
      <div><dt>Photos + Files import</dt><dd>Ready</dd></div>
      <div><dt>PNG gallery export</dt><dd>Ready</dd></div>
    </dl>
  </aside>
</section>

<section class="section" aria-labelledby="principles-title">
  <div class="section-heading">
    <p class="eyebrow">A studio, not a toy box</p>
    <h2 id="principles-title">The artwork gets the whole screen.</h2>
    <p>Coloring Room keeps navigation and organization in the sidebar, then lets the canvas, Apple Pencil, and native palette own the creative space.</p>
  </div>
  <div class="principle-grid">
    <article class="principle-card"><span class="card-number">01</span><h3>Pick from a real library</h3><p>Browse built-in and imported drawings through smart folders, favorites, complexity, orientation, custom categories, and search.</p></article>
    <article class="principle-card"><span class="card-number">02</span><h3>Color the natural way</h3><p>Draw, erase, zoom, pan, fill regions, manage layers, and undo across the combined edit history with native PencilKit behavior.</p></article>
    <article class="principle-card"><span class="card-number">03</span><h3>Finish beyond the canvas</h3><p>Export an opaque, aligned PNG, keep it in the Gallery, share it, or return through the medium home-screen widget.</p></article>
  </div>
</section>

<section class="section section--split" id="studio-flow" aria-labelledby="studio-title">
  <article class="resident-card">
    <div class="resident-card__header"><div class="resident-icon" aria-hidden="true"><span></span><span></span><span></span></div><div><p class="eyebrow">Template Studio</p><h2 id="studio-title">One canvas, every layer aligned</h2></div></div>
    <p class="resident-card__summary">The template, fills, PencilKit strokes, and overlays share one native zoom and pan viewport, so close detail work stays exactly where you placed it.</p>
    <div class="boundary-note"><strong>Your library can grow</strong><span>Built-ins · Photos · Files · Custom folders</span></div>
    <ul class="capability-list">
      <li><span aria-hidden="true">✓</span> Drawing-specific strokes, fills, layers, and recent colors</li>
      <li><span aria-hidden="true">✓</span> Favorites, In Progress, Completed, Recent, and Hidden</li>
      <li><span aria-hidden="true">✓</span> Reorderable built-in and custom folders</li>
      <li><span aria-hidden="true">✓</span> Full-resolution Gallery with compact thumbnails</li>
    </ul>
  </article>
  <div class="run-flow" aria-labelledby="flow-title">
    <p class="eyebrow">From blank page to gallery</p><h2 id="flow-title">Pick. Color. Keep.</h2>
    <ol>
      <li><span>01</span><div><strong>Choose a drawing</strong><p>Browse a folder or search its titles.</p></div></li>
      <li><span>02</span><div><strong>Set the tool</strong><p>Use the native PencilKit palette.</p></div></li>
      <li><span>03</span><div><strong>Draw or fill</strong><p>Color naturally at any zoom level.</p></div></li>
      <li><span>04</span><div><strong>Return anytime</strong><p>Per-drawing progress restores automatically.</p></div></li>
      <li><span>05</span><div><strong>Send to Gallery</strong><p>Composite the artwork at full fidelity.</p></div></li>
      <li><span>06</span><div><strong>Share the PNG</strong><p>Export through the system share sheet.</p></div></li>
    </ol>
  </div>
</section>

<section class="section foundation" aria-labelledby="foundation-title">
  <div><p class="eyebrow">Offline first. Recoverable by design.</p><h2 id="foundation-title">Creative work should come back.</h2></div>
  <p>Coloring Room saves drawings and imports locally with atomic writes, then mirrors templates, progress, library state, and Gallery artwork to iCloud when available. The studio remains usable without a network, and deferred recovery handles iCloud arriving late.</p>
</section>
