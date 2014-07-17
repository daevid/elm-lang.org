
import Website.Skeleton (skeleton)
import Window

port title : String
port title = "Blazing Fast HTML"

main = lift (skeleton "Blog" everything) Window.dimensions

everything wid =
  let w  = truncate (toFloat wid * 0.8)
      w' = min 600 w
      section txt =
          let words = width w' txt in
          container w (heightOf words) middle words
  in
  flow down
  [ width w pageTitle
  , section intro
  ]

pageTitle = [markdown|
<br/>
<div style="font-family: futura, 'century gothic', 'twentieth century', calibri, verdana, helvetica, arial; text-align: center;">
<div style="font-size: 4em;">Blazing Fast HTML</div>
<div style="font-size: 1.5em;">Virtual DOM in Elm</div>
</div>
|]

intro = [markdown|
<style type="text/css">
p, li {
  text-align: justify;
  line-height: 1.5em;
}
pre { background-color: white;
      padding: 10px;
      border: 1px solid rgb(216, 221, 225);
      border-radius: 4px;
}
code > span.kw { color: #268BD2; }
code > span.dt { color: #268BD2; }
code > span.dv, code > span.bn, code > span.fl { color: #D33682; }
code > span.ch { color: #DC322F; }
code > span.st { color: #2AA198; }
code > span.co { color: #93A1A1; }
code > span.ot { color: #A57800; }
code > span.al { color: #CB4B16; font-weight: bold; }
code > span.fu { color: #268BD2; }
code > span.re { }
code > span.er { color: #D30102; font-weight: bold; }
</style>

<br/>The new [elm-html][] library lets you use
HTML and CSS directly in Elm. Want to use flexbox? Want to keep using existing
style sheets? Elm now makes all of this pleasant and *fast*. For example, when
recreating the [TodoMVC][todo] app, the [code][code] is quite simple and our
[preliminary benchmarks][bench] show that it is extremely fast compared to other
popular entries:

[elm-html]: http://library.elm-lang.org/catalog/evancz-elm-html/latest/
[todo]: http://evancz.github.io/elm-todomvc/
[code]: https://github.com/evancz/elm-html/blob/master/examples/todo/Todo.elm
[bench]: https://evancz.github.io/todomvc-perf-comparison

<a href="https://evancz.github.io/todomvc-perf-comparison">
<img src="/diagrams/sampleResults.png"
     alt="sample results with Chrome 35 on a Macbook Air with OSX 10.9.4"
     style="width:500px; height:380px; margin-left: auto; margin-right: auto; display:block;"></a>

Both Elm and Mercury are based on the [virtual-dom][] project, which is entirely
responsible for great performance numbers. The first half of this post will
explore what &ldquo;virtual DOM&rdquo; means and how **purity** and
**immutability** make it extremely fast. This will explain why Om, Mercury, and
Elm all get such great numbers.

[virtual-dom]: https://github.com/Matt-Esch/virtual-dom

Performance is a good hook, but the real benefit is that this approach leads to
code that is easier to understand and maintain. In short, it becomes very simple
to create reusable HTML widgets and abstract out common patterns. *This* is why
people with larger code bases should be interested in virtual DOM approaches.

This library is also great news for people who have been thinking about using
Elm. It means you can use Elm *and* keep using the same CSS and
designer/developer workflow that you are comfortable with. It is simpler than
ever to get the benefits of Elm in your project. Let&rsquo;s see how it works.

[FRP]: /learn/What-is-FRP.elm
[std]: library.elm-lang.org/catalog/elm-lang-Elm/latest/
[com]: library.elm-lang.org/catalog/

## Virtual DOM

This library is based on the idea of a &ldquo;virtual DOM&rdquo;. Rather than
touching the DOM directly, we build an abstract version of it on each frame. We
use the `node` function to create a cheap representation of what we want:

```haskell
node : String -> [Attribute] -> [CssProperty] -> [Html] -> Html
```

This lets us specify a tag, a list of HTML attributes, a list of CSS properties,
and a list of children. For example, we can use `node` to build a simple
`profile` widget that shows a user&rsquo;s picture and name:

```haskell
profile : User -> Html
profile user =
    node "div" [ "className" := "profile" ] []
      [ node "img" [ "src" := user.picture ] [] []
      , node "span" [] [] [ text user.name ]
      ]
```

Notice that we set a class so the whole thing can be styled from CSS. Paired
with Elm&rsquo;s module system, this makes it easy to abstract out common
patterns and reuse code. We will explore more example uses soon in the section
on [reusable widgets](#reusable-widgets).

## Making Virtual DOM Fast

Virtual DOM sound pretty slow right? Create a whole new scene on every frame?
This technique is actually [widely used in the game industry][scene] and
performs shockingly well for DOM updates when you use two relatively simple
techniques: diffing and laziness.

[scene]: http://en.wikipedia.org/wiki/Scene_graph

React popularized the idea of &ldquo;diffing&rdquo; to figure out how the DOM
needs to be modified. **Diffing means taking the *current* virtual DOM and the
*new* virtual DOM and looking for changes.** It sounds kind of fancy at first,
but it is a very simple process. We first make a big list of all the
differences, like if someone has changed the color of a particular `<div>` or
added an entirely new one. After all of the differences are found, we use them
as instructions for modifying the DOM in one big batch using
[`requestAnimationFrame`][raf]. This means we do the dirty work of modifying
the DOM and making sure everything is fast. You can focus on writing code
that is easy to understand and maintain.

[raf]: https://developer.mozilla.org/en/docs/Web/API/window.requestAnimationFrame

This approach created a clear path to fully supporting HTML and CSS in a way
that is perfect for Elm! Even better, Elm already has great facilities for
purity and immutability, which are vital for optimizations that make diffing
*way* faster.

One of the tricks that came from Om is being lazy about diffing. For example,
lets say we are rendering a list of tasks:

```haskell
todoList : [Task] -> Html
todoList tasks =
    node "div" [] [] (map todoItem tasks)
```

But we may know that on many updates, none of the tasks are changing. And if no
task changes, the view must not be changing either. This is a perfect time to be
`lazy`:

```haskell
lazy : (a -> Html) -> a -> Html

todoWidget : State -> Html
todoWidget state =
    lazy todoList state.tasks
```

Instead of calling the `todoList` function on every frame, we check to see if
`state.tasks` has changed since last frame. If not, we can skip everything.
No need to call the function, do any diffing, or touch the DOM at all!
This optimization is safe in Elm because functions are [pure][] and data is
[immutable][].

  * **Purity** means that the `todoList` function will *always* have
    the same output given the same input. So if we know `state.tasks` is the same,
    we can skip `todoList` entirely.

  * **Immutability** makes it cheap to figure out when things are &ldquo;the
    same&rdquo;. Immutability guarantees that if two things are referentially
    equal, they *must* be structurally equal.

So we just check to see if `todoList` and `state.tasks` are the same as last
frame by comparing the old and new values by *reference*. This is super cheap,
and if they are the same, the `lazy` function can often avoid a ton of work.
This is a pretty simple trick that can speed things up significantly.

[pure]: http://en.wikipedia.org/wiki/Pure_function
[immutable]: http://en.wikipedia.org/wiki/Immutable_object

If you have been following Elm, you may begin to see a pattern:
purity and immutability are kind of a big deal. Read about [hot-swapping in
Elm](/blog/Interactive-Programming.elm) and the [time traveling
debugger](http://debug.elm-lang.org/) to learn more about this.

## Reusable Widgets

This approach makes it is incredibly simple to create reusable widgets. For
example, a list of user profiles can be nicely abstracted with something like
this:

```haskell
import Html (..)

profiles : [User] -> Html
profiles users =
    node "div" [] [] (map profile users)

profile : User -> Html
profile user =
    node "div" [] []
    [ node "img" [ "src" := user.picture ] [] []
    , text user.name
    ]
```

We now have a `profiles` widget that takes a list of users and gives us back
some HTML. It is easy to reuse anywhere, and unlike templating languages, we can
use any part of Elm to help create widgets like this. We can even begin to
create community libraries for common widgets or patterns.

If you want to create complex styles, those can be abstracted out and reused
too! In the following example, we define a `font` and `background` that
can be mixed and matched on any node.

```haskell
-- small reusable CSS properties
font : [CssProperty]
font =
    [ "font-family" := "futura, sans-serif"
    , "color"       := "rgb(42, 42, 42)"
    , "font-size"   := "2em"
    ]

background : [CssProperty]
background =
    [ "background-color" := "rgb(245, 245, 245)" ]

-- combine them to make individual nodes
profiles : [User] -> Html
profiles users =
    node "div" [] (font ++ background) (map profile users)
```

So creating reusable widgets and abstracting out common patterns is extremely
simple now, but we can do much more than this!

## Freedom of Abstraction

When I started working on the project that would become Elm, HTML was about 20
years old and people still had to read three blog posts and five Stack Overflow
questions to figure out how to vertically center things. My initial goal with
Elm was rethink GUIs from scratch. **What would web programming look like if we
could restart?**

[elm-html][] has two very important strengths in pursuing that goal. First, it
gives you access to HTML and CSS, so you can always take full advantage of the
latest features. Second, it makes it possible to create *new* abstractions.

This means **HTML and CSS become the basic building blocks for *nicer*
abstractions.** For example, it may be possible to recreate Elm&rsquo;s
`Element` abstraction using this library. But most importantly, *anyone* can
experiment with new ways to make views more modular and pleasant. Paul Chiusano
explains this aspiration very nicely in his [provocative post on CSS][css].

[css]: http://pchiusano.github.io/2014-07-02/css-is-unnecessary.html

My goal with Elm is still to rethink web programming, and in a weird and twisted
way, fully supporting HTML and CSS is a big step in that direction. I am excited
to see what we can do with [elm-html](https://github.com/evancz/elm-html)!

## Thank you

Thank you to React and Om for discovering and popularizing these techniques.
Thank you in particular to Sebastian Markbage, David Nolen, Matt Esch, and Jake
Verbaten who helped me *understand* them.

Huge thanks to Matt Esch and Jake Verbaten who created [virtual-dom][] and
[mercury][], which this library is based on. They are fully responsible for
the great performance!

[mercury]: https://github.com/Raynos/mercury

|]
